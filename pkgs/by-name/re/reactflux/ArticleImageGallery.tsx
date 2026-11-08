// The caller supplies the existing lightbox preview and safe attachment link.
// Editorial figures stay in the article HTML; this gallery is only for images
// that the article image model did not already find there.
import type { ReactNode } from "react";
interface GalleryProps<T extends { url: string }> {
  items: readonly T[];
  renderPreview: (item: T) => ReactNode;
  renderName: (item: T) => ReactNode;
}
const ArticleImageGallery = <T extends { url: string }>({
  items,
  renderPreview,
  renderName,
}: GalleryProps<T>) => (
  <div className="article-image-gallery">
    {items.map((item) => (
      <figure key={item.url} className="article-image-figure">
        {renderPreview(item)}
        <figcaption>{renderName(item)}</figcaption>
      </figure>
    ))}
  </div>
);

export default ArticleImageGallery;
