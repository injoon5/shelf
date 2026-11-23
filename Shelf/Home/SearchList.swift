import UIKit

/// Search's list, as App Library's: a section per first letter under a bold
/// letter, rows of icon and name with a separator from the name's edge, a
/// cloud on an app that isn't downloaded, and the A–Z # index beside it all.
/// Once something is typed, one list of matches, best first, and no index.
/// The field it filters by is the bar's (`SearchBar`), below it.
///
/// It follows `HomeModel.query` and `LibraryStore` in `updateProperties()`,
/// which UIKit tracks for observation, so it changes as they do.
@MainActor
final class SearchList: UIView, UICollectionViewDelegate, UIGestureRecognizerDelegate {
    private let model: HomeModel
    private let library: LibraryStore

    let collectionView: UICollectionView
    private var dataSource: UICollectionViewDiffableDataSource<String, String>!
    private let index = SearchIndexView()
    private let empty = UIContentUnavailableView(configuration: .empty())
    private let backgroundTap = UITapGestureRecognizer()

    /// What the list shows now.
    private(set) var shown = SearchSections([], query: "")

    /// A tap on a row.
    var onOpen: (String) -> Void = { _ in }
    /// The list was pulled down past its top and let go (velocity in pt/s,
    /// down), or a tap landed on no row: search closes.
    var onClose: (CGFloat) -> Void = { _ in }

    /// Where the list starts, below the status bar, and where the field's
    /// top is now (the keyboard moves it): the list scrolls between them.
    var top: CGFloat = 0 { didSet { if top != oldValue { setNeedsLayout() } } }
    var fieldTop: CGFloat = 0 { didSet { if fieldTop != oldValue { setNeedsLayout() } } }

    /// Rows whose app's card stands in for them: their icon isn't drawn.
    var cardIcons: Set<String> = [] {
        didSet {
            guard cardIcons != oldValue else { return }
            for case let row as SearchRow in collectionView.visibleCells { row.hidesArt = cardIcons.contains(row.id) }
        }
    }

    init(model: HomeModel, library: LibraryStore) {
        self.model = model
        self.library = library
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        super.init(frame: .zero)
        collectionView.collectionViewLayout = UICollectionViewCompositionalLayout { [unowned self] _, environment in
            var list = UICollectionLayoutListConfiguration(appearance: .plain)
            list.backgroundColor = .clear
            // Separators are the rows' own: App Library's are a whole point,
            // and a list's are a pixel.
            list.showsSeparators = false
            // Letters over the sections only with nothing typed.
            list.headerMode = shown.isIndexed ? .supplementary : .none
            list.headerTopPadding = 0
            let section = NSCollectionLayoutSection.list(using: list, layoutEnvironment: environment)
            // Below the soft edges, as the rows are: a list's headers
            // otherwise sit above them and stay sharp under the field.
            for header in section.boundarySupplementaryItems { header.zIndex = -1 }
            return section
        }

        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.showsVerticalScrollIndicator = false
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .onDrag
        collectionView.scrollsToTop = false
        collectionView.delegate = self
        // The rows scroll under the status bar, and under the field, softly.
        collectionView.topEdgeEffect.style = .soft
        collectionView.bottomEdgeEffect.style = .soft
        addSubview(collectionView)

        let rows = UICollectionView.CellRegistration<SearchRow, String> { [unowned self] row, _, id in
            configure(row, id: id)
        }
        let headers = UICollectionView.SupplementaryRegistration<SearchHeader>(elementKind: UICollectionView.elementKindSectionHeader) {
            [unowned self] header, _, indexPath in
            header.title = shown.sections.indices.contains(indexPath.section) ? shown.sections[indexPath.section].title : nil
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { view, indexPath, id in
            view.dequeueConfiguredReusableCell(using: rows, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { view, _, indexPath in
            view.dequeueConfiguredReusableSupplementary(using: headers, for: indexPath)
        }

        index.onSelect = { [unowned self] title in scroll(toIndexTitle: title) }
        addSubview(index)

        // "No Results" carries the app's text-size cap, as other words over
        // the Home Screen do; the rows carry their own.
        empty.overrideUserInterfaceStyle = .dark
        empty.maximumContentSizeCategory = UIContentSizeCategory(ShelfMetrics.textSizeCap)
        empty.isUserInteractionEnabled = false
        empty.isHidden = true
        addSubview(empty)

        backgroundTap.addTarget(self, action: #selector(tappedBackground))
        backgroundTap.cancelsTouchesInView = false
        backgroundTap.delegate = self
        collectionView.addGestureRecognizer(backgroundTap)

        maximumContentSizeCategory = UIContentSizeCategory(ShelfMetrics.textSizeCap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Following the models

    override func updateProperties() {
        super.updateProperties()
        let sections = SearchSections(library.items, query: model.query)
        // Read here so a download starting or ending redraws its row.
        _ = library.downloading
        apply(sections)
        if sections.sections.isEmpty, !model.query.isEmpty {
            var configuration = UIContentUnavailableConfiguration.search()
            configuration.text = String(localized: "No Results for “\(model.query)”")
            configuration.secondaryText = String(localized: "Check the spelling or try a new search.")
            empty.configuration = configuration
            empty.isHidden = false
        } else {
            empty.isHidden = true
        }
    }

    private func apply(_ sections: SearchSections) {
        let reordered = sections != shown
        let headersChanged = sections.isIndexed != shown.isIndexed
        shown = sections
        if headersChanged { collectionView.collectionViewLayout.invalidateLayout() }
        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        for section in sections.sections {
            let id = section.title ?? "matches"
            snapshot.appendSections([id])
            snapshot.appendItems(section.ids, toSection: id)
        }
        // Names, icons and downloads change in place.
        snapshot.reconfigureItems(sections.ids)
        index.isHidden = !sections.isIndexed
        // As App Library's: what's typed changes the list at once.
        dataSource.apply(snapshot, animatingDifferences: false)
        if reordered {
            // Headers (and which rows are last in their section) follow.
            let kind = UICollectionView.elementKindSectionHeader
            for path in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
                (collectionView.supplementaryView(forElementKind: kind, at: path) as? SearchHeader)?.title = shown.sections[safe: path.section]?.title
            }
        }
    }

    private func configure(_ row: SearchRow, id: String) {
        guard let item = library.item(id) else { return }
        let path = dataSource.indexPath(for: id)
        let last = path.map { $0.item == (shown.sections[safe: $0.section]?.ids.count ?? 0) - 1 } ?? false
        row.configure(item, isDownloading: library.downloading.contains(id), showsSeparator: !last)
        row.hidesArt = cardIcons.contains(id)
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        collectionView.frame = bounds
        let inset = UIEdgeInsets(top: top, left: 0, bottom: max(bounds.height - fieldTop + SearchMetrics.fieldGap, 0), right: 0)
        if collectionView.contentInset != inset {
            let atTop = collectionView.contentOffset.y <= -collectionView.contentInset.top + 0.5
            collectionView.contentInset = inset
            if atTop { collectionView.contentOffset.y = -inset.top }
        }
        let width = SearchMetrics.indexHitWidth
        let center = bounds.width - SearchMetrics.indexCenterFromTrailing
        index.frame = CGRect(x: center - width / 2, y: top, width: width, height: max(fieldTop - SearchMetrics.fieldGap - top, 0))
        empty.frame = CGRect(x: 0, y: top, width: bounds.width, height: max(fieldTop - top, 0))
    }

    /// Back to the top of the list, as it is each time search opens.
    func scrollToTop() {
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.contentInset.top), animated: false)
    }

    // MARK: Where rows are

    /// Where `id`'s icon is, in `space`'s coordinates, whether or not its
    /// row is on screen: what a card opened from search grows out of and
    /// lands on.
    func iconFrame(for id: String, in space: UIView) -> CGRect? {
        guard !isHidden, alpha > 0, let path = dataSource.indexPath(for: id),
              let attributes = collectionView.layoutAttributesForItem(at: path) else { return nil }
        let size = SearchMetrics.iconSize
        let icon = CGRect(x: attributes.frame.minX + SearchMetrics.iconLeading, y: attributes.frame.midY - size / 2, width: size, height: size)
        return collectionView.convert(icon, to: space)
    }

    // MARK: The index

    private func scroll(toIndexTitle title: String) {
        guard let section = shown.section(forIndexTitle: title) else { return }
        let path = IndexPath(item: 0, section: section)
        collectionView.layoutIfNeeded()
        guard let header = collectionView.layoutAttributesForSupplementaryElement(ofKind: UICollectionView.elementKindSectionHeader, at: path)
            ?? collectionView.layoutAttributesForItem(at: path) else { return }
        let inset = collectionView.adjustedContentInset
        let highest = max(collectionView.contentSize.height + inset.bottom - collectionView.bounds.height, -inset.top)
        let y = min(max(header.frame.minY - inset.top, -inset.top), highest)
        collectionView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
    }

    // MARK: Touches

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        onOpen(id)
    }

    /// Let go pulled down past the top: search closes, carrying the finger's speed.
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let overscroll = -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
        guard overscroll > SearchMetrics.closePull else { return }
        // Stop the bounce where it is, so the list goes with the rest of search.
        targetContentOffset.pointee = scrollView.contentOffset
        onClose(scrollView.panGestureRecognizer.velocity(in: self).y)
    }

    @objc private func tappedBackground() {
        onClose(0)
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Only on the backdrop between and below the rows.
        let point = touch.location(in: collectionView)
        if collectionView.indexPathForItem(at: point) != nil { return false }
        if let view = touch.view, view.isDescendant(of: index) { return false }
        return true
    }

    // MARK: The icon's menu

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let path = indexPaths.first, let id = dataSource.itemIdentifier(for: path), let item = library.item(id) else { return nil }
        return UIContextMenuConfiguration(identifier: id as NSString, previewProvider: nil) { [unowned self] _ in
            let groups = item.menu(model: model, library: library).map { group in
                UIMenu(options: .displayInline, children: group.map { action in
                    var attributes: UIMenuElement.Attributes = []
                    if action.isDestructive { attributes.insert(.destructive) }
                    if !action.isEnabled { attributes.insert(.disabled) }
                    return UIAction(title: action.title, image: UIImage(systemName: action.symbol), attributes: attributes) { _ in
                        action.perform()
                    }
                })
            }
            return UIMenu(children: groups)
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfiguration configuration: UIContextMenuConfiguration,
                        highlightPreviewForItemAt indexPath: IndexPath) -> UITargetedPreview? {
        iconPreview(at: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfiguration configuration: UIContextMenuConfiguration,
                        dismissalPreviewForItemAt indexPath: IndexPath) -> UITargetedPreview? {
        iconPreview(at: indexPath)
    }

    /// The row's icon, cut to its outline, lifts for the menu, as an icon
    /// on the Home Screen does.
    private func iconPreview(at indexPath: IndexPath) -> UITargetedPreview? {
        guard let row = collectionView.cellForItem(at: indexPath) as? SearchRow else { return nil }
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(cgPath: IconPath.path(row.art.bounds, radius: HomeMetrics.iconRadius(SearchMetrics.iconSize)))
        return UITargetedPreview(view: row.art, parameters: parameters)
    }
}

/// One row: the icon, the name, a cloud if it isn't downloaded, and the
/// separator under it, from the name's leading edge to the trailing inset.
final class SearchRow: UICollectionViewListCell {
    private(set) var id = ""
    let art = IconArtView(face: .settings, iconSize: SearchMetrics.iconSize)
    private let name = UILabel()
    private let cloud = UIImageView()
    private let separator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundConfiguration = .clear()
        name.font = .preferredFont(forTextStyle: SearchMetrics.nameTextStyle)
        name.adjustsFontForContentSizeCategory = true
        name.textColor = .white
        name.lineBreakMode = .byTruncatingTail
        cloud.image = UIImage(systemName: "icloud.and.arrow.down",
                              withConfiguration: UIImage.SymbolConfiguration(textStyle: SearchMetrics.nameTextStyle, scale: .medium))
        cloud.tintColor = .white
        cloud.contentMode = .scaleAspectFit
        separator.backgroundColor = UIColor(white: 1, alpha: SearchMetrics.separatorOpacity)
        for view in [art, name, cloud, separator] as [UIView] { contentView.addSubview(view) }
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ item: HomeItem, isDownloading: Bool, showsSeparator: Bool) {
        id = item.id
        art.face = item.face
        let isRunnable = item.app?.isRunnable ?? true
        // An app that isn't here yet keeps its colours, with the cloud
        // beside it, until it's downloading: then the pie, as on its icon.
        art.setPending(isRunnable: isRunnable || !isDownloading, isDownloading: isDownloading)
        cloud.isHidden = isRunnable || isDownloading
        name.text = item.name
        separator.isHidden = !showsSeparator
        accessibilityLabel = item.name
        accessibilityHint = cloud.isHidden ? nil : String(localized: "Downloads and opens")
        setNeedsLayout()
    }

    var hidesArt = false {
        didSet { art.isHidden = hidesArt }
    }

    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { art.setPressed(isHighlighted) } }
    }

    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontal: UILayoutPriority,
                                          verticalFittingPriority vertical: UILayoutPriority) -> CGSize {
        CGSize(width: targetSize.width, height: SearchMetrics.rowHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        let size = SearchMetrics.iconSize
        art.center = CGPoint(x: SearchMetrics.iconLeading + size / 2, y: bounds.midY)
        let end = bounds.width - SearchMetrics.trailingInset
        var textEnd = end
        if !cloud.isHidden {
            let height = SearchMetrics.cloudWidth * (cloud.image.map { $0.size.height / max($0.size.width, 1) } ?? 1)
            let cloudEnd = end - SearchMetrics.cloudTrailing
            cloud.frame = CGRect(x: cloudEnd - SearchMetrics.cloudWidth, y: bounds.midY - height / 2,
                                 width: SearchMetrics.cloudWidth, height: height)
            textEnd = cloud.frame.minX - 8
        }
        name.frame = CGRect(x: SearchMetrics.textLeading, y: 0, width: max(textEnd - SearchMetrics.textLeading, 0), height: bounds.height)
        separator.frame = CGRect(x: SearchMetrics.textLeading, y: bounds.height - SearchMetrics.separatorHeight,
                                 width: end - SearchMetrics.textLeading, height: SearchMetrics.separatorHeight)
    }
}

/// A section's letter, bold, in line with the icons.
final class SearchHeader: UICollectionReusableView {
    private let label = UILabel()

    var title: String? {
        didSet { label.text = title }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .systemFont(ofSize: SearchMetrics.headerFontSize, weight: .bold))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        addSubview(label)
        accessibilityTraits = .header
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontal: UILayoutPriority,
                                          verticalFittingPriority vertical: UILayoutPriority) -> CGSize {
        CGSize(width: targetSize.width, height: title == nil ? 0 : SearchMetrics.headerHeight)
    }

    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let fitted = super.preferredLayoutAttributesFitting(attributes)
        fitted.size.height = title == nil ? 0 : SearchMetrics.headerHeight
        return fitted
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.sizeToFit()
        // Placed by its baseline, as the reference measures it.
        let baseline = bounds.height - SearchMetrics.headerBaseline
        label.frame.origin = CGPoint(x: SearchMetrics.iconLeading, y: (baseline - label.font.ascender).rounded(toScale: traitCollection.displayScale))
    }
}

private extension CGFloat {
    func rounded(toScale scale: CGFloat) -> CGFloat {
        let scale = scale > 0 ? scale : 3
        return (self * scale).rounded() / scale
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
