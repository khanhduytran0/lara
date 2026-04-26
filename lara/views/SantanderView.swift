//
//  SantanderView.swift
//  symlin2k
//
//  Created by ruter on 15.02.26.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AVKit
import AVFoundation
import QuickLook

struct SantanderView: View {
    let startPath: String
    @State private var selectedmethod: method = .hybrid
    @ObservedObject private var mgr = laramgr.shared

    init(startPath: String = "/") {
        self.startPath = startPath.isEmpty ? "/" : startPath
    }

    var body: some View {
        let readUsesSBX = (selectedmethod != .vfs)
        let writeUsesVFS = (selectedmethod != .sbx)
        let ready = mgr.vfsready && mgr.sbxready
        Group {
            if ready {
                SantanderBrowserSheet(startPath: startPath, readUsesSBX: readUsesSBX, writeUsesVFS: writeUsesVFS)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 36, weight: .semibold))
                    
                    Text("File Manager not ready")
                        .font(.headline)
                    
                    Text("1. Switch to hybrid mode in settings \n2. Escape the Sandbox \n3. Initialise VFS\n4. Try again.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            refreshSelectedMethod()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            refreshSelectedMethod()
        }
    }
}

private extension SantanderView {
    func refreshSelectedMethod() {
        if let raw = UserDefaults.standard.string(forKey: "selectedmethod"),
           let m = method(rawValue: raw) {
            selectedmethod = m
        }
    }
}

struct SantanderBrowserSheet: UIViewControllerRepresentable {
    let startPath: String
    let readUsesSBX: Bool
    let writeUsesVFS: Bool
    private static var cachedNav: UINavigationController?

    func makeUIViewController(context: Context) -> UINavigationController {
        if let nav = Self.cachedNav {
            return nav
        }
        let root = SantanderPathListViewController(
            path: SantanderPath(path: startPath, isDirectory: true),
            readUsesSBX: readUsesSBX,
            useVFSOverwrite: writeUsesVFS
        )
        let nav = UINavigationController(rootViewController: root)
        Self.cachedNav = nav
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // no-op
    }
}

struct SantanderPath: Hashable {
    let path: String
    let lastPathComponent: String
    let isDirectory: Bool
    let contentType: UTType?
    let displayName: String

    var displayImage: UIImage? {
        if isDirectory { return UIImage(systemName: "folder.fill") }
        guard let type = contentType else { return UIImage(systemName: "doc") }
        if type.isSubtype(of: .text) { return UIImage(systemName: "doc.text") }
        if type.isSubtype(of: .image) { return UIImage(systemName: "photo") }
        if type.isSubtype(of: .audio) { return UIImage(systemName: "waveform") }
        if type.isSubtype(of: .movie) || type.isSubtype(of: .video) { return UIImage(systemName: "play") }
        return UIImage(systemName: "doc")
    }

    init(path: String, isDirectory: Bool, displayName: String? = nil) {
        self.path = path
        self.lastPathComponent = path == "/" ? "/" : (path as NSString).lastPathComponent
        self.displayName = displayName ?? self.lastPathComponent
        self.isDirectory = isDirectory
        let ext = (path as NSString).pathExtension
        self.contentType = ext.isEmpty ? nil : UTType(filenameExtension: ext)
    }
}

final class SantanderPathListViewController: UITableViewController, UISearchResultsUpdating, UISearchBarDelegate, UIDocumentPickerDelegate {
    private struct ClipboardItem {
        let path: String
        let isDirectory: Bool
        let name: String
    }

    private static var clipboard: ClipboardItem?

    private var unfilteredContents: [SantanderPath]
    private var renderedContents: [SantanderPath]
    private let currentPath: SantanderPath
    private let readUsesSBX: Bool
    private let useVFSOverwrite: Bool
    private var initialEmptyStateMessage: String?
    private var isSearching = false
    private var displayHiddenFiles = true
    @AppStorage("fmRecursiveSearch") private var fmRecursiveSearch: Bool = false

    init(path: SantanderPath, readUsesSBX: Bool, useVFSOverwrite: Bool) {
        self.readUsesSBX = readUsesSBX
        self.useVFSOverwrite = useVFSOverwrite
        let initialListing = Self.loadDirectoryContents(for: path, readUsesSBX: readUsesSBX)
        self.currentPath = path
        self.unfilteredContents = initialListing.items
        self.renderedContents = initialListing.items
        self.initialEmptyStateMessage = initialListing.emptyStateMessage
        super.init(style: .insetGrouped)
        self.title = path.path == "/" ? "/" : path.lastPathComponent
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.title = currentPath.path == "/" ? "/" : currentPath.lastPathComponent

        setRightBarButton()

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.searchBar.delegate = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        applyFilters()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationItem.title = currentPath.path == "/" ? "/" : currentPath.lastPathComponent
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        renderedContents.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if shouldShowFooter() {
            return "This File Manager is very unreliable and overall shitty. For more information, look at the info button. \nIT MAY DISPLAY INACCURATE INFORMATION!"
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let item = renderedContents[indexPath.row]
        
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            guard let self else { return UIMenu() }
            
            let copyAction = UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                self?.copyItem(item)
            }
            
            let infoAction = UIAction(title: "Get Info", image: UIImage(systemName: "info.circle")) { [weak self] _ in
                self?.showInfoForItem(item)
            }
            
            let replaceAction = UIAction(
                title: "Replace With Clipboard",
                image: UIImage(systemName: "doc.on.clipboard"),
                attributes: (Self.clipboard == nil || (!self.readUsesSBX && !self.useVFSOverwrite)) ? [.disabled] : []
            ) { [weak self] _ in
                self?.replaceItem(item)
            }
            
            let chmodAction = UIAction(
                title: "Chmod",
                image: UIImage(systemName: "lock.open")
            ) { [weak self] _ in
                self?.presentChmodDialog(for: item)
            }
            
            let chownAction = UIAction(
                title: "Chown",
                image: UIImage(systemName: "person.crop.circle")
            ) { [weak self] _ in
                self?.presentChownDialog(for: item)
            }
            
            let deleteAction = UIAction(
                title: "Delete",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.confirmDelete(item)
            }
            return UIMenu(children: [
                copyAction,
                infoAction,
                replaceAction,
                chmodAction,
                chownAction,
                deleteAction
            ])
        })
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let path = renderedContents[indexPath.row]
        return pathCellRow(forURL: path, displayFullPathAsSubtitle: isSearching)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let path = renderedContents[indexPath.row]
        if path.isDirectory {
            let vc = SantanderPathListViewController(path: path, readUsesSBX: readUsesSBX, useVFSOverwrite: useVFSOverwrite)
            navigationController?.pushViewController(vc, animated: true)
        } else {
            let vc = SantanderFileReaderViewController(path: path, readUsesSBX: readUsesSBX, useVFSOverwrite: useVFSOverwrite)
            navigationController?.pushViewController(vc, animated: true)
        }
    }

    private func applyFilters(query: String = "") {
        if !query.isEmpty {
            isSearching = true

            if fmRecursiveSearch {
                DispatchQueue.global(qos: .userInitiated).async {
                    let results = self.recursiveSearchSBX(
                        at: self.currentPath.path,
                        query: query
                    )

                    DispatchQueue.main.async {
                        self.renderedContents = results
                        self.updateEmptyState(query: query)
                        self.tableView.reloadData()
                    }
                }
            } else {
                var results: [SantanderPath] = []

                for item in unfilteredContents {
                    if item.displayName.localizedCaseInsensitiveContains(query) {
                        results.append(item)
                    }
                }

                renderedContents = results
                updateEmptyState(query: query)
                tableView.reloadData()
            }

            return
        }

        isSearching = false

        var items = unfilteredContents
        if !displayHiddenFiles {
            items = items.filter { !$0.lastPathComponent.starts(with: ".") }
        }

        renderedContents = items
        updateEmptyState(query: query)
        tableView.reloadData()
    }

    private func updateEmptyState(query: String) {
        guard renderedContents.isEmpty else {
            tableView.backgroundView = nil
            return
        }

        let message: String
        if !query.isEmpty {
            message = "No matching items."
        } else if !displayHiddenFiles && !unfilteredContents.isEmpty {
            message = "No visible items. Enable \"Display hidden files\" to show dotfiles."
        } else {
            message = initialEmptyStateMessage ?? "Directory is empty."
        }

        let label = UILabel()
        label.text = message
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        tableView.backgroundView = label
    }

    private static func loadDirectoryContents(for path: SantanderPath, readUsesSBX: Bool) -> (items: [SantanderPath], emptyStateMessage: String?) {
        guard path.isDirectory else { return ([], "Not a directory.") }

        let mgr = laramgr.shared
        if readUsesSBX {
            guard mgr.sbxready else { return ([], "Sandbox escape not ready.") }
            return loadDirectoryContentsSBX(for: path)
        }

        guard mgr.vfsready else { return ([], "Not ready.") }
        guard let entries = mgr.vfslistdir(path: path.path) else {
            return ([], "Unable to list directory.")
        }

        let items = entries.map { entry in
            let name = entry.name
            let fullPath = path.path == "/" ? "/" + name : path.path + "/" + name
            return SantanderPath(path: fullPath, isDirectory: entry.isDir)
        }

        if items.isEmpty {
            return ([], "Directory is empty.")
        }

        return (items, nil)
    }
    
    private func recursiveSearchSBX(at rootPath: String, query: String) -> [SantanderPath] {
        let fm = FileManager.default
        var results: [SantanderPath] = []

        guard let enumerator = fm.enumerator(atPath: rootPath) else { return [] }

        for case let item as String in enumerator {
            let fullPath = (rootPath as NSString).appendingPathComponent(item)

            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)

            if item.localizedCaseInsensitiveContains(query) ||
               fullPath.localizedCaseInsensitiveContains(query) {
                results.append(SantanderPath(path: fullPath, isDirectory: isDir.boolValue))
            }
        }

        return results
    }

    private static func loadDirectoryContentsSBX(for path: SantanderPath) -> (items: [SantanderPath], emptyStateMessage: String?) {
        let fm = FileManager.default
        var isDir = ObjCBool(false)
        let exists = fm.fileExists(atPath: path.path, isDirectory: &isDir)
        if !exists || !isDir.boolValue {
            return ([], "Directory no longer exists.")
        }
        if !fm.isReadableFile(atPath: path.path) {
            return ([], "Cannot list directory (missing permissions).")
        }
        do {
            let entries = try fm.contentsOfDirectory(atPath: path.path)
            let modeRaw = UserDefaults.standard.string(forKey: "selectedFmAppsDisplayMode")
            let mode = fmAppsDisplayMode(rawValue: modeRaw ?? "") ?? .appName

            let dataAppPaths = [
                "/private/var/mobile/Containers/Data/Application",
                "/var/mobile/Containers/Data/Application"
            ]
            let bundleAppPaths = [
                "/private/var/containers/Bundle/Application",
                "/var/containers/Bundle/Application"
            ]
            var bundleIDNameCache: [String:String] = [:]
            if mode == .appName && dataAppPaths.contains(path.path) {
                let bundlePath = "/private/var/containers/Bundle/Application"
                let apps = try fm.contentsOfDirectory(atPath: bundlePath)
                var results: [String:String] = [:]
                for app in apps {
                    let appPath = bundlePath + "/" + app
                    let contents = try fm.contentsOfDirectory(atPath: appPath)
                    for item in contents {
                        if item.hasSuffix(".app") {
                            if let plist = NSDictionary(contentsOf: URL(fileURLWithPath: appPath + "/" + item + "/Info.plist")),
                                let bundleID = plist["CFBundleIdentifier"] as? String,
                                let appName = 
                                    (plist["CFBundleDisplayName"] as? String) ??
                                    (plist["CFBundleName"] as? String) ??
                                    (plist["CFBundleExecutable"] as? String) {
                                results[bundleID] = appName
                            }
                            break
                        }
                    }
                }
                bundleIDNameCache = results
            }
            let items = entries.map { name in
                let fullPath = path.path == "/" ? "/" + name : path.path + "/" + name
                var isDir: ObjCBool = false
                var displayName = name
                fm.fileExists(atPath: fullPath, isDirectory: &isDir)

                if (bundleAppPaths + dataAppPaths).contains(path.path) {
                    if mode == .appName {
                        if bundleAppPaths.contains(path.path) {
                            if let contents = try? fm.contentsOfDirectory(atPath: fullPath) {
                                for item in contents {
                                    if item.hasSuffix(".app") {
                                        if let plist = NSDictionary(contentsOf: URL(fileURLWithPath: fullPath + "/" + item + "/Info.plist")),
                                            let appName = 
                                                (plist["CFBundleDisplayName"] as? String) ??
                                                (plist["CFBundleName"] as? String) ??
                                                (plist["CFBundleExecutable"] as? String) {
                                            displayName = appName
                                        }
                                        break
                                    }
                                }
                            }
                        } else {
                            if let plist = NSDictionary(contentsOf: URL(fileURLWithPath: fullPath + "/.com.apple.mobile_container_manager.metadata.plist")),
                                let bundleID = plist["MCMMetadataIdentifier"] as? String {
                                displayName = bundleIDNameCache[bundleID] ?? bundleID
                            }
                        }

                    } else if mode == .bundleID {
                        if let plist = NSDictionary(contentsOf: URL(fileURLWithPath: fullPath + "/.com.apple.mobile_container_manager.metadata.plist")), let bundleID = plist["MCMMetadataIdentifier"] as? String {
                            displayName = bundleID
                        }
                    }
                }

                return SantanderPath(path: fullPath, isDirectory: isDir.boolValue, displayName: displayName)
            }
            if items.isEmpty {
                return ([], "Directory is empty.")
            }
            return (items, nil)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError {
                return ([], "Cannot list directory (missing permissions).")
            }
            return ([], "Unable to list directory: \(nsError.localizedDescription)")
        }
    }

    private static func isSBXSelected() -> Bool {
        if let raw = UserDefaults.standard.string(forKey: "selectedmethod") {
            return raw.uppercased() == "SBX"
        }
        return false
    }
    private func setRightBarButton() {
        let menuButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: makeRightBarButton()
        )
        if shouldShowFooter() {
            let infoButton = UIBarButtonItem(
                image: UIImage(systemName: "info.circle"),
                style: .plain,
                target: self,
                action: #selector(showInfo)
            )
            navigationItem.rightBarButtonItems = [menuButton, infoButton]
        } else {
            navigationItem.rightBarButtonItems = [menuButton]
        }
    }

    private func makeRightBarButton() -> UIMenu {
        let uploadAction = UIAction(
            title: "Upload File",
            image: UIImage(systemName: "square.and.arrow.down")
        ) { [weak self] _ in
            self?.presentUploadPicker()
        }
        let pasteAction = UIAction(
            title: "Paste",
            image: UIImage(systemName: "doc.on.clipboard"),
            attributes: (Self.clipboard == nil || !readUsesSBX) ? [.disabled] : []
        ) { [weak self] _ in
            self?.pasteClipboardItem()
        }
        let pasteReplaceAction = UIAction(
            title: "Paste (Replace)",
            image: UIImage(systemName: "doc.on.clipboard.fill"),
            attributes: (Self.clipboard == nil || !readUsesSBX) ? [.disabled] : []
        ) { [weak self] _ in
            self?.pasteClipboardItem(replaceExisting: true)
        }
        let sortAZ = UIAction(title: "Sort A-Z", image: UIImage(systemName: "textformat")) { [weak self] _ in
            guard let self else { return }
            self.unfilteredContents.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            self.applyFilters(query: self.navigationItem.searchController?.searchBar.text ?? "")
        }
        let sortZA = UIAction(title: "Sort Z-A", image: UIImage(systemName: "textformat")) { [weak self] _ in
            guard let self else { return }
            self.unfilteredContents.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedDescending }
            self.applyFilters(query: self.navigationItem.searchController?.searchBar.text ?? "")
        }
        let toggleHidden = UIAction(title: "Display hidden files", image: UIImage(systemName: "eye"), state: displayHiddenFiles ? .on : .off) { [weak self] _ in
            guard let self else { return }
            self.displayHiddenFiles.toggle()
            self.applyFilters(query: self.navigationItem.searchController?.searchBar.text ?? "")
        }
        let goRoot = UIAction(title: "Go to Root", image: UIImage(systemName: "externaldrive")) { [weak self] _ in
            guard let self else { return }
            let vc = SantanderPathListViewController(path: SantanderPath(path: "/", isDirectory: true), readUsesSBX: readUsesSBX, useVFSOverwrite: useVFSOverwrite)
            self.navigationController?.setViewControllers([vc], animated: true)
        }
        let goHome = UIAction(title: "Go to Home", image: UIImage(systemName: "house")) { [weak self] _ in
            guard let self else { return }
            let vc = SantanderPathListViewController(path: SantanderPath(path: NSHomeDirectory(), isDirectory: true), readUsesSBX: readUsesSBX, useVFSOverwrite: useVFSOverwrite)
            self.navigationController?.setViewControllers([vc], animated: true)
        }
        let sortMenu = UIMenu(title: "Sort by..", image: UIImage(systemName: "arrow.up.arrow.down"), children: [sortAZ, sortZA])
        let viewMenu = UIMenu(title: "View", image: UIImage(systemName: "eye"), children: [toggleHidden])
        let goMenu = UIMenu(title: "Go to..", image: UIImage(systemName: "arrow.right"), children: [goRoot, goHome])
        return UIMenu(children: [uploadAction, pasteAction, pasteReplaceAction, sortMenu, viewMenu, goMenu])
    }

    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        isSearching = !query.isEmpty
        applyFilters(query: query)
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        isSearching = false
        applyFilters(query: "")
    }

    private func pathCellRow(forURL fsItem: SantanderPath, displayFullPathAsSubtitle useSubtitle: Bool = false) -> UITableViewCell {
        let pathName = fsItem.displayName
        let cell = UITableViewCell(style: useSubtitle ? .subtitle : .default, reuseIdentifier: nil)
        var conf = cell.defaultContentConfiguration()
        conf.text = pathName
        conf.image = fsItem.displayImage

        if pathName.first == "." {
            conf.textProperties.color = .gray
            conf.secondaryTextProperties.color = .gray
        }
        if useSubtitle {
            conf.secondaryText = fsItem.path
        }
        if fsItem.isDirectory {
            cell.accessoryType = .disclosureIndicator
        }
        cell.contentConfiguration = conf
        return cell
    }

    private func shouldShowFooter() -> Bool {
        return !readUsesSBX
    }

    @objc private func showInfo() {
        let msg = """
        This browser is powered by vfs namecache lookups, not full directory enumeration. Therefore, some folders (eg. /private/var) may appear empty unless entries are already cached.
        Symlinks may then also be shown as files even when their targets are directories.
        
        tldr; This File Manager is unreliable and sometimes completely inaccurate. If it works or not is basically 100% up to luck.
        """
        let alert = UIAlertController(title: "File Manager Info", message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func copyItem(_ item: SantanderPath) {
        Self.clipboard = ClipboardItem(path: item.path, isDirectory: item.isDirectory, name: item.lastPathComponent)
        let alert = UIAlertController(title: "Copied", message: item.lastPathComponent, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
        setRightBarButton()
    }

    private func pasteClipboardItem(replaceExisting: Bool = false) {
        guard readUsesSBX else {
            let alert = UIAlertController(title: "Paste Unavailable", message: "Paste is only supported in SBX mode.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        guard let clip = Self.clipboard else { return }

        let destDir = currentPath.path
        if clip.isDirectory {
            if destDir == clip.path || destDir.hasPrefix(clip.path + "/") {
                let alert = UIAlertController(title: "Paste Failed", message: "Cannot paste a folder into itself.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
                return
            }
        }

        let baseDest = (destDir as NSString).appendingPathComponent(clip.name)
        let dest = replaceExisting ? baseDest : uniqueDestinationPath(base: baseDest)

        do {
            if replaceExisting && FileManager.default.fileExists(atPath: dest) {
                try FileManager.default.removeItem(atPath: dest)
            }
            try FileManager.default.copyItem(atPath: clip.path, toPath: dest)
            reloadContents()
        } catch {
            let alert = UIAlertController(title: "Paste Failed", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func uniqueDestinationPath(base: String) -> String {
        let fm = FileManager.default
        if !fm.fileExists(atPath: base) { return base }

        let dir = (base as NSString).deletingLastPathComponent
        let file = (base as NSString).lastPathComponent
        let ext = (file as NSString).pathExtension
        let stem = ext.isEmpty ? file : (file as NSString).deletingPathExtension

        var i = 1
        while true {
            let suffix = i == 1 ? " copy" : " copy \(i)"
            let newName = ext.isEmpty ? "\(stem)\(suffix)" : "\(stem)\(suffix).\(ext)"
            let candidate = (dir as NSString).appendingPathComponent(newName)
            if !fm.fileExists(atPath: candidate) { return candidate }
            i += 1
        }
    }

    private func reloadContents() {
        let listing = Self.loadDirectoryContents(for: currentPath, readUsesSBX: readUsesSBX)
        unfilteredContents = listing.items
        initialEmptyStateMessage = listing.emptyStateMessage
        applyFilters(query: navigationItem.searchController?.searchBar.text ?? "")
    }

    private func confirmDelete(_ item: SantanderPath) {
        let alert = UIAlertController(title: "Delete", message: "Delete \(item.lastPathComponent)?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteItem(item)
        })
        present(alert, animated: true)
    }
    
    func showResultAlert(success: Bool, title: String) {
        let alert = UIAlertController(
            title: title,
            message: success ? "Operation completed." : "Operation failed.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    func presentChmodDialog(for item: SantanderPath) {
        let alert = UIAlertController(
            title: "Chmod",
            message: item.lastPathComponent,
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "e.g. 755"
            textField.keyboardType = .numberPad
        }
        
        let apply = UIAlertAction(title: "Apply", style: .default) { [weak self] _ in
            guard
                let self,
                let text = alert.textFields?.first?.text,
                let mode = UInt16(text, radix: 8)
            else { return }
            
            item.path.withCString { cPath in
                let result = apfs_mod(cPath, mode)
                
                DispatchQueue.main.async {
                    self.showResultAlert(
                        success: result == 0,
                        title: "Chmod"
                    )
                }
            }
        }
        
        alert.addAction(apply)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    func presentChownDialog(for item: SantanderPath) {
        let alert = UIAlertController(
            title: "Chown",
            message: item.lastPathComponent,
            preferredStyle: .alert
        )
        
        alert.addTextField { tf in
            tf.placeholder = "UID (e.g. 501)"
            tf.keyboardType = .numberPad
        }
        
        alert.addTextField { tf in
            tf.placeholder = "GID (e.g. 501)"
            tf.keyboardType = .numberPad
        }
        
        let apply = UIAlertAction(title: "Apply", style: .default) { [weak self] _ in
            guard
                let self,
                let uidText = alert.textFields?[0].text,
                let gidText = alert.textFields?[1].text,
                let uid = UInt32(uidText),
                let gid = UInt32(gidText)
            else { return }
            
            item.path.withCString { cPath in
                let result = apfs_own(cPath, uid, gid)
                
                DispatchQueue.main.async {
                    self.showResultAlert(
                        success: result == 0,
                        title: "Chown"
                    )
                }
            }
        }
        
        alert.addAction(apply)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }

    private func deleteItem(_ item: SantanderPath) {
        guard readUsesSBX else {
            let alert = UIAlertController(title: "Delete Unavailable", message: "Delete is only supported in SBX mode.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        do {
            try FileManager.default.removeItem(atPath: item.path)
            reloadContents()
        } catch {
            let alert = UIAlertController(title: "Delete Failed", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func replaceItem(_ item: SantanderPath) {
        guard let clip = Self.clipboard else { return }
        if useVFSOverwrite {
            if !item.isDirectory && !clip.isDirectory {
                replaceItemVFS(item, clip: clip)
                return
            }
            if readUsesSBX {
                replaceItemSBX(item, clip: clip)
                return
            }
            let alert = UIAlertController(title: "Replace Unavailable", message: "Replace is only supported in SBX mode.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        guard readUsesSBX else {
            let alert = UIAlertController(title: "Replace Unavailable", message: "Replace is only supported in SBX mode.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        if clip.isDirectory {
            if item.path == clip.path || item.path.hasPrefix(clip.path + "/") {
                let alert = UIAlertController(title: "Replace Failed", message: "Cannot replace with a folder into itself.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
                return
            }
        }
        do {
            if FileManager.default.fileExists(atPath: item.path) {
                try FileManager.default.removeItem(atPath: item.path)
            }
            try FileManager.default.copyItem(atPath: clip.path, toPath: item.path)
            reloadContents()
        } catch {
            let alert = UIAlertController(title: "Replace Failed", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func replaceItemVFS(_ item: SantanderPath, clip: ClipboardItem) {
        let mgr = laramgr.shared
        guard mgr.vfsready else {
            let alert = UIAlertController(title: "VFS Not Ready", message: "Run VFS init before overwriting files.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let ok = mgr.vfsoverwritefromlocalpath(target: item.path, source: clip.path)
        if ok {
            reloadContents()
        } else {
            let alert = UIAlertController(title: "Replace Failed", message: "VFS overwrite failed.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func replaceItemSBX(_ item: SantanderPath, clip: ClipboardItem) {
        if clip.isDirectory {
            if item.path == clip.path || item.path.hasPrefix(clip.path + "/") {
                let alert = UIAlertController(title: "Replace Failed", message: "Cannot replace with a folder into itself.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
                return
            }
        }
        do {
            if FileManager.default.fileExists(atPath: item.path) {
                try FileManager.default.removeItem(atPath: item.path)
            }
            try FileManager.default.copyItem(atPath: clip.path, toPath: item.path)
            reloadContents()
        } catch {
            let alert = UIAlertController(title: "Replace Failed", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func showInfoForItem(_ item: SantanderPath) {
        let details = fileDetails(for: item.path)
        let alert = UIAlertController(title: item.lastPathComponent, message: details, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func fileDetails(for path: String) -> String {
        let fm = FileManager.default
        var lines: [String] = []

        var isDir = ObjCBool(false)
        let exists = fm.fileExists(atPath: path, isDirectory: &isDir)
        lines.append("Exists: \(exists ? "yes" : "no")")
        if exists {
            lines.append("Kind: \(isDir.boolValue ? "directory" : "file")")
        }

        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .contentTypeKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .isSymbolicLinkKey
        ]

        if let values = try? url.resourceValues(forKeys: keys) {
            if let type = values.contentType {
                lines.append("UTType: \(type.identifier)")
            }
            if let size = values.fileSize {
                lines.append("Size: \(size) bytes")
            }
            if let created = values.creationDate {
                lines.append("Created: \(created)")
            }
            if let modified = values.contentModificationDate {
                lines.append("Modified: \(modified)")
            }
            if let isSym = values.isSymbolicLink {
                lines.append("Symlink: \(isSym ? "yes" : "no")")
            }
        }

        if let attrs = try? fm.attributesOfItem(atPath: path) {
            if let perms = attrs[.posixPermissions] as? NSNumber {
                lines.append(String(format: "POSIX perms: %04o", perms.intValue))
            }

            if let owner = attrs[.ownerAccountName] as? String {
                lines.append("Owner: \(owner)")
            }
            if let group = attrs[.groupOwnerAccountName] as? String {
                lines.append("Group: \(group)")
            }
        }

        lines.append("Readable: \(fm.isReadableFile(atPath: path) ? "yes" : "no")")
        lines.append("Writable: \(fm.isWritableFile(atPath: path) ? "yes" : "no")")
        lines.append("Executable: \(fm.isExecutableFile(atPath: path) ? "yes" : "no")")

        return lines.joined(separator: "\n")
    }

    private func presentUploadPicker() {
        guard readUsesSBX else {
            let alert = UIAlertController(title: "Upload Unavailable", message: "Upload is only supported in SBX mode.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else {
            let alert = UIAlertController(title: "Upload Failed", message: "Unable to access selected file.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let destDir = currentPath.path
        let baseDest = (destDir as NSString).appendingPathComponent(url.lastPathComponent)
        let dest = uniqueDestinationPath(base: baseDest)

        do {
            if FileManager.default.fileExists(atPath: dest) {
                try FileManager.default.removeItem(atPath: dest)
            }
            try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: dest))
            reloadContents()
        } catch {
            let alert = UIAlertController(title: "Upload Failed", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}

final class SantanderFileReaderViewController: UIViewController, QLPreviewControllerDataSource, UISearchResultsUpdating, UISearchBarDelegate {
    private let readUsesSBX: Bool
    private let useVFSOverwrite: Bool
    private let path: SantanderPath
    private let textView = UITextView()
    private let imageView = UIImageView()
    private var playerVC: AVPlayerViewController?
    private var tempURL: URL?
    private var tempSize: Int64 = 0
    private var isEditingFile = false
    private var isEditableText = false
    private var editButton: UIBarButtonItem?
    private var originalText: String = ""
    private var isTextPreview = false
    private let searchController = UISearchController(searchResultsController: nil)

    init(path: SantanderPath, readUsesSBX: Bool, useVFSOverwrite: Bool) {
        self.path = path
        self.readUsesSBX = readUsesSBX
        self.useVFSOverwrite = useVFSOverwrite
        super.init(nibName: nil, bundle: nil)
        self.title = path.lastPathComponent
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        textView.isEditable = false
        textView.alwaysBounceVertical = true
        textView.alwaysBounceVertical = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .label

        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true

        view.addSubview(textView)
        view.addSubview(imageView)
        textView.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            imageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        searchController.searchResultsUpdater = self
        searchController.searchBar.delegate = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        let canEdit = readUsesSBX || useVFSOverwrite
        if canEdit {
            let edit = UIBarButtonItem(title: "Edit", style: .plain, target: self, action: #selector(toggleEdit))
            edit.isEnabled = true
            editButton = edit
            navigationItem.rightBarButtonItems = [
                edit,
                UIBarButtonItem(title: "Preview", style: .plain, target: self, action: #selector(showPreview)),
                UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(showShare))
            ]
        } else {
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(title: "Preview", style: .plain, target: self, action: #selector(showPreview)),
                UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(showShare))
            ]
        }

        loadFile()
    }

    private func loadFile() {
        let mgr = laramgr.shared
        if readUsesSBX {
            if isImagePath(path) {
                guard let data = readFileSBX(maxBytes: 8 * 1024 * 1024) else {
                    setTextPreview("Failed to read file.\n\n" + unreadableFileDetails(for: path.path), editable: false)
                    return
                }
                if let image = UIImage(data: data) {
                    imageView.image = image
                    imageView.isHidden = false
                    textView.isHidden = true
                    isTextPreview = false
                    return
                }
            }

            if isMediaPath(path) {
                if prepareTempFileIfNeeded(maxBytes: 128 * 1024 * 1024) {
                    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
                    try? AVAudioSession.sharedInstance().setActive(true, options: [])
                    let player = AVPlayer(url: tempURL!)
                    let pvc = AVPlayerViewController()
                    pvc.player = player
                    addChild(pvc)
                    pvc.view.frame = view.bounds
                    pvc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    view.addSubview(pvc.view)
                    pvc.didMove(toParent: self)
                    playerVC = pvc
                    player.play()
                    isTextPreview = false
                    return
                } else {
                    textView.text = "Failed to prepare media file."
                    return
                }
            }

            guard let data = readFileSBX(maxBytes: 2 * 1024 * 1024) else {
                setTextPreview("Failed to read file.\n\n" + unreadableFileDetails(for: path.path), editable: false)
                return
            }
            let rendered = render(data: data)
            setTextPreview(rendered.text, editable: rendered.isEditable)
            return
        }

        if isImagePath(path) {
            guard let data = mgr.vfsread(path: path.path, maxSize: 8 * 1024 * 1024) else {
                textView.text = "Failed to read file."
                return
            }
            if let image = UIImage(data: data) {
                imageView.image = image
                imageView.isHidden = false
                textView.isHidden = true
                isTextPreview = false
                return
            }
        }

        if isMediaPath(path) {
            if prepareTempFileIfNeeded(maxBytes: 128 * 1024 * 1024) {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
                try? AVAudioSession.sharedInstance().setActive(true, options: [])
                let player = AVPlayer(url: tempURL!)
                let pvc = AVPlayerViewController()
                pvc.player = player
                addChild(pvc)
                pvc.view.frame = view.bounds
                pvc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                view.addSubview(pvc.view)
                pvc.didMove(toParent: self)
                playerVC = pvc
                player.play()
                isTextPreview = false
                return
            } else {
                textView.text = "Failed to prepare media file."
                return
            }
        }

        guard let data = mgr.vfsread(path: path.path, maxSize: 2 * 1024 * 1024) else {
            textView.text = "Failed to read file."
            return
        }
        let rendered = render(data: data)
        setTextPreview(rendered.text, editable: rendered.isEditable)
    }

    @objc private func toggleEdit() {
        if isEditingFile {
            saveEdits()
        } else {
            guard isTextPreview else {
                let alert = UIAlertController(title: "Edit Unavailable", message: "This file type isn't editable in the viewer.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
                return
            }
            isEditingFile = true
            textView.isEditable = true
            textView.becomeFirstResponder()
            editButton?.title = "Save"
        }
    }

    private func saveEdits() {
        let data = Data(textView.text.utf8)
        if useVFSOverwrite {
            let mgr = laramgr.shared
            guard mgr.vfsready else {
                let alert = UIAlertController(title: "VFS Not Ready", message: "Run VFS init before overwriting files.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
                return
            }
            let ok = mgr.vfsoverwritewithdata(target: path.path, data: data)
            if ok {
                isEditingFile = false
                textView.isEditable = false
                textView.resignFirstResponder()
                editButton?.title = "Edit"
                let alert = UIAlertController(title: "Saved", message: "File updated.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            } else {
                let alert = UIAlertController(title: "Save Failed", message: "VFS overwrite failed.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
            return
        }

        do {
            try data.write(to: URL(fileURLWithPath: path.path), options: .atomic)
            isEditingFile = false
            textView.isEditable = false
            textView.resignFirstResponder()
            editButton?.title = "Edit"
            let alert = UIAlertController(title: "Saved", message: "File updated.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        } catch {
            let alert = UIAlertController(title: "Save Failed", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func readFileSBX(maxBytes: Int) -> Data? {
        let url = URL(fileURLWithPath: path.path)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        if #available(iOS 13.4, *) {
            return try? handle.read(upToCount: maxBytes) ?? Data()
        }
        return handle.readData(ofLength: maxBytes)
    }

    private func fileSizeSBX() -> Int64? {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
           let size = attrs[.size] as? NSNumber {
            return size.int64Value
        }
        return nil
    }

    private func render(data: Data) -> (text: String, isEditable: Bool) {
        if data.isEmpty {
            return ("(empty file)", true)
        }

        if let plist = decodePropertyList(from: data) {
            return (plist, false)
        }

        if let text = decodeText(from: data) {
            return (text, true)
        }

        return (binaryPreview(from: data), false)
    }

    private func setEditableText(_ editable: Bool) {
        isEditableText = editable
    }

    private func setTextPreview(_ text: String, editable: Bool) {
        isTextPreview = true
        originalText = text
        textView.isHidden = false
        imageView.isHidden = true
        textView.text = text
        textView.attributedText = nil
        setEditableText(editable)
        applySearch(query: searchController.searchBar.text ?? "")
    }

    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text ?? ""
        applySearch(query: query)
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        applySearch(query: "")
    }

    private func applySearch(query: String) {
        guard isTextPreview else { return }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            textView.text = originalText
            return
        }

        let base = originalText as NSString
        let fullRange = NSRange(location: 0, length: base.length)
        let attributed = NSMutableAttributedString(string: originalText)
        attributed.addAttribute(.font, value: textView.font ?? UIFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: fullRange)

        var foundRanges: [NSRange] = []
        var searchRange = fullRange
        while true {
            let range = base.range(of: q, options: [.caseInsensitive], range: searchRange)
            if range.location == NSNotFound { break }
            foundRanges.append(range)
            let nextLoc = range.location + max(range.length, 1)
            if nextLoc >= base.length { break }
            searchRange = NSRange(location: nextLoc, length: base.length - nextLoc)
        }

        for r in foundRanges {
            attributed.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.35), range: r)
        }

        textView.attributedText = attributed

        if let first = foundRanges.first {
            textView.scrollRangeToVisible(first)
        }
    }

    private func isImagePath(_ path: SantanderPath) -> Bool {
        if let type = path.contentType, type.isSubtype(of: .image) { return true }
        let ext = (path.path as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "heif", "bmp", "tif", "tiff", "webp"].contains(ext)
    }

    private func isMediaPath(_ path: SantanderPath) -> Bool {
        if let type = path.contentType {
            if type.isSubtype(of: .audio) || type.isSubtype(of: .movie) || type.isSubtype(of: .video) { return true }
        }
        let ext = (path.path as NSString).pathExtension.lowercased()
        if ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext) { return true }
        if [
            "mp3", "m4a", "m4b", "m4p", "aac", "aiff", "aif", "aifc", "wav", "wave",
            "caf", "flac", "alac", "opus", "oga", "ogg", "mka", "wma", "ac3", "eac3",
            "amr", "3gp", "3gpp", "3g2", "au", "snd", "mp2", "mp1", "ape", "tta", "wv"
        ].contains(ext) { return true }
        return false
    }

    private func decodePropertyList(from data: Data) -> String? {
        guard data.starts(with: Data("bplist".utf8)) || data.starts(with: Data("<?xml".utf8)) else {
            return nil
        }

        guard let plistObject = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return nil
        }

        if JSONSerialization.isValidJSONObject(plistObject),
           let jsonData = try? JSONSerialization.data(withJSONObject: plistObject, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: jsonData, encoding: .utf8) {
            return json
        }

        if let xmlData = try? PropertyListSerialization.data(fromPropertyList: plistObject, format: .xml, options: 0),
           let xml = String(data: xmlData, encoding: .utf8) {
            return xml
        }

        return String(describing: plistObject)
    }

    private func decodeText(from data: Data) -> String? {
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .utf32,
            .utf32LittleEndian,
            .utf32BigEndian,
            .ascii,
            .isoLatin1,
            .windowsCP1252,
            .macOSRoman,
            .nonLossyASCII
        ]

        for encoding in encodings {
            guard let value = String(data: data, encoding: encoding) else { continue }
            if looksLikeText(value) {
                return value
            }
        }
        return nil
    }

    private func looksLikeText(_ value: String) -> Bool {
        if value.isEmpty { return true }
        let scalars = value.unicodeScalars
        let disallowed = scalars.filter { scalar in
            let v = scalar.value
            if v == 9 || v == 10 || v == 13 { return false }
            if v < 32 { return true }
            if v >= 0x7F && v <= 0x9F { return true }
            return false
        }
        return Double(disallowed.count) / Double(scalars.count) < 0.01
    }

    private func binaryPreview(from data: Data) -> String {
        let limit = min(data.count, 4096)
        let chunk = data.prefix(limit)
        var lines: [String] = []
        lines.append("Binary data (\(data.count) bytes). Showing first \(limit) bytes:")
        lines.append("")

        var offset = 0
        while offset < chunk.count {
            let row = chunk[offset..<min(offset + 16, chunk.count)]
            let hex = row.map { String(format: "%02X", $0) }.joined(separator: " ")
            let ascii = row.map { byte -> String in
                if byte >= 32 && byte <= 126 { return String(UnicodeScalar(byte)) }
                return "."
            }.joined()
            lines.append(String(format: "%08X  %-47@  %@", offset, hex as NSString, ascii))
            offset += 16
        }

        return lines.joined(separator: "\n")
    }

    private func unreadableFileDetails(for path: String) -> String {
        let fm = FileManager.default
        var lines: [String] = []

        var isDir = ObjCBool(false)
        let exists = fm.fileExists(atPath: path, isDirectory: &isDir)
        lines.append("Exists: \(exists ? "yes" : "no")")
        if exists {
            lines.append("Kind: \(isDir.boolValue ? "directory" : "regular item")")
        }

        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .contentTypeKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
            .fileSizeKey
        ]
        if let values = try? url.resourceValues(forKeys: keys) {
            if let type = values.contentType {
                lines.append("UTType: \(type.identifier)")
            }
            if let size = values.fileSize {
                lines.append("Size: \(size) bytes")
            }
            if let isSymLink = values.isSymbolicLink {
                lines.append("Symlink: \(isSymLink ? "yes" : "no")")
            }
            if values.isSymbolicLink == true,
               let target = try? fm.destinationOfSymbolicLink(atPath: path) {
                lines.append("Symlink target: \(target)")
            }
            if let isAlias = values.isAliasFile {
                lines.append("Alias file: \(isAlias ? "yes" : "no")")
            }
        }

        if let attrs = try? fm.attributesOfItem(atPath: path) {
            if let fileType = attrs[.type] as? FileAttributeType {
                lines.append("File attribute type: \(fileType.rawValue)")
            }
            let ownerName = attrs[.ownerAccountName] as? String
            let ownerID = (attrs[.ownerAccountID] as? NSNumber)?.intValue
            switch (ownerName, ownerID) {
            case let (name?, id?):
                lines.append("Owner: \(name) (\(id))")
            case let (name?, nil):
                lines.append("Owner: \(name)")
            case let (nil, id?):
                lines.append("Owner ID: \(id)")
            default:
                break
            }

            let groupName = attrs[.groupOwnerAccountName] as? String
            let groupID = (attrs[.groupOwnerAccountID] as? NSNumber)?.intValue
            switch (groupName, groupID) {
            case let (name?, id?):
                lines.append("Group: \(name) (\(id))")
            case let (name?, nil):
                lines.append("Group: \(name)")
            case let (nil, id?):
                lines.append("Group ID: \(id)")
            default:
                break
            }
            if let perms = attrs[.posixPermissions] as? NSNumber {
                lines.append(String(format: "POSIX perms: %04o", perms.intValue))
            }
        }

        lines.append("Readable: \(fm.isReadableFile(atPath: path) ? "yes" : "no")")
        lines.append("Writable: \(fm.isWritableFile(atPath: path) ? "yes" : "no")")
        lines.append("Executable: \(fm.isExecutableFile(atPath: path) ? "yes" : "no")")

        return lines.joined(separator: "\n")
    }

    @objc private func showPreview() {
        guard prepareTempFileIfNeeded(maxBytes: 128 * 1024 * 1024) else {
            textView.text = "Failed to prepare preview."
            return
        }
        let ql = QLPreviewController()
        ql.dataSource = self
        present(ql, animated: true)
    }

    @objc private func showShare() {
        guard prepareTempFileIfNeeded(maxBytes: 128 * 1024 * 1024) else {
            textView.text = "Failed to prepare share."
            return
        }
        let av = UIActivityViewController(activityItems: [tempURL!], applicationActivities: nil)
        present(av, animated: true)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { tempURL == nil ? 0 : 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return tempURL! as QLPreviewItem
    }

    private func prepareTempFileIfNeeded(maxBytes: Int64) -> Bool {
        if let url = tempURL, FileManager.default.fileExists(atPath: url.path) { return true }

        if readUsesSBX {
            guard let size = fileSizeSBX(), size > 0 else { return false }
            if size > maxBytes {
                textView.text = "File too large to preview (\(size) bytes)."
                return false
            }
            tempURL = URL(fileURLWithPath: path.path)
            tempSize = size
            return true
        }

        let size = vfs_filesize(path.path)
        guard size > 0 else { return false }
        if size > maxBytes {
            textView.text = "File too large to preview (\(size) bytes)."
            return false
        }

        let ext = (path.path as NSString).pathExtension
        let filename = "santander_" + UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        FileManager.default.createFile(atPath: url.path, contents: nil)

        guard let handle = try? FileHandle(forWritingTo: url) else { return false }
        defer { try? handle.close() }

        let chunk = 1024 * 1024
        var offset: Int64 = 0
        while offset < size {
            let toRead = Int(min(Int64(chunk), size - offset))
            var buf = [UInt8](repeating: 0, count: toRead)
            let n = vfs_read(path.path, &buf, toRead, off_t(offset))
            if n <= 0 { return false }
            handle.write(Data(buf.prefix(Int(n))))
            offset += Int64(n)
        }

        tempURL = url
        tempSize = size
        return true
    }
}
