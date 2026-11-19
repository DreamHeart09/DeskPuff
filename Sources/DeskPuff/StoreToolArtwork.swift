import AppKit

func storeToolArtwork(productID: String) -> NSImage? {
    guard let url = Bundle.module.url(
        forResource: productID,
        withExtension: "png",
        subdirectory: "Resources/StoreTools"
    ) else { return nil }
    return NSImage(contentsOf: url)
}
