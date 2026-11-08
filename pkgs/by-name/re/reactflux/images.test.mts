import assert from "node:assert/strict";
import test from "node:test";
import { createServer } from "vite";
import { htmlToDOM } from "html-react-parser";
import { renderToStaticMarkup } from "react-dom/server";
import { createElement, type ComponentType } from "react";
interface ParserNode {
  name?: string;
  data?: string;
  attribs?: Record<string, string>;
  parent?: ParserNode | null;
  children?: ParserNode[];
}
interface FixtureNode extends ParserNode {
  children: FixtureNode[];
  readonly textContent: string;
  readonly tagName: string | undefined;
  getAttribute(name: string): string | null;
  hasAttribute(name: string): boolean;
  closest(name: string): ParserNode | null;
  querySelectorAll(selector: string): FixtureNode[];
  querySelector(selector: string): FixtureNode | null;
}
interface Attachment {
  url: string;
  kind: string;
  canPreview: boolean;
  galleryIndex?: number;
}
interface EntryInput {
  content?: string;
  enclosures?: Array<{ url: string; mime_type?: string }>;
}
interface Entry {
  content: string;
  coverSource: string | null;
  attachments: {
    images: Attachment[];
    items: Attachment[];
    primaryMedia: Attachment | null;
  };
}
interface ImageModel {
  visibleAttachments: Attachment[];
  imageSlides: Array<{ src: string }>;
  getImageIndex(url: string): number;
}
interface EnclosureProps {
  items: Attachment[];
  onImagePreview(): void;
  onOpenChange(): void;
  open: boolean;
}

// Feed HTML uses the same parser dependency as the reader. This small adapter
// supplies the DOM operations used by the entry and gallery models in Node.
const wrap = (raw: ParserNode): FixtureNode => {
  // Preserve parser node identity and supply only the operations used by the models.
  const children = (raw.children ?? []).map(wrap);
  // The descriptor API adds accessor fields that its generic return type cannot infer.
  const node = Object.defineProperties(
    Object.assign(raw, {
      children,
      getAttribute: (name: string) => raw.attribs?.[name] ?? null,
      hasAttribute: (name: string) => name in (raw.attribs ?? {}),
      closest: (name: string) =>
        raw.parent?.name === name ? raw.parent : null,
      querySelectorAll: (selector: string): FixtureNode[] => {
        const names = new Set(selector.split(",").map((name) => name.trim()));
        const matches: FixtureNode[] = [];
        for (const child of children) {
          if (child.name && names.has(child.name)) matches.push(child);
          matches.push(...child.querySelectorAll(selector));
        }
        return matches;
      },
      querySelector: (selector: string): FixtureNode | null =>
        node.querySelectorAll(selector)[0] ?? null,
    }),
    {
      tagName: { get: () => raw.name?.toUpperCase() },
      textContent: {
        get: () =>
          raw.data ?? children.map((child) => child.textContent).join(""),
      },
    },
  );
  // oxlint-disable-next-line typescript/no-unsafe-type-assertion -- defineProperties installs the typed accessors above.
  return node as FixtureNode;
};
// This partial DOM adapter intentionally implements only the reader model contract.
Object.defineProperty(globalThis, "DOMParser", {
  configurable: true,
  value: class {
    parseFromString(html: string): FixtureNode {
      return wrap({ children: htmlToDOM(html) });
    }
  },
});
const proxy = (url: string): string =>
  `https://reader.example.test/proxy/${"a".repeat(43)}=/${Buffer.from(url).toString("base64url")}`;
const server = await createServer({
  configFile: false,
  // SSR fixtures need JSX transformation; Vite provides it without the
  // development refresh plugin and its optional compiler dependencies.
  oxc: { jsx: { runtime: "automatic" } },
  optimizeDeps: { noDiscovery: true, include: [] },
  server: { middlewareMode: true },
  plugins: [
    {
      name: "fixture-language",
      enforce: "pre",
      resolveId(id) {
        if (id.endsWith("/src/hooks/useLanguage")) return "\0fixture-language";
        return null;
      },
      load(id) {
        if (id === "\0fixture-language")
          return `import { atom } from 'nanostores'; export const polyglotState = atom({ polyglot: { t: (key, options = {}) => key + ' ' + (options.count ?? options.name ?? '') } });`;
        return null;
      },
    },
  ],
  resolve: { alias: { "@": `${process.cwd()}/src` } },
});
function defaultFunction(
  value: unknown,
): value is { default: (...args: never[]) => unknown } {
  return (
    value !== null &&
    typeof value === "object" &&
    "default" in value &&
    typeof value.default === "function"
  );
}
function entryModule(
  value: unknown,
): value is { default: (input: EntryInput) => Entry } {
  return defaultFunction(value);
}
function imageModule(value: unknown): value is {
  default: (content: string, attachments: Attachment[]) => ImageModel;
} {
  return defaultFunction(value);
}
const entries: unknown = await server.ssrLoadModule(
  "/src/utils/entry-presentation.js",
);
const images: unknown = await server.ssrLoadModule("/src/utils/images.js");
if (!entryModule(entries) || !imageModule(images))
  throw new Error("Missing reader model exports");
const prepareEntry = entries.default;
const buildArticleImageModel = images.default;

try {
  await test("prepared covers prefer supplied responsive images and preserve signatures", () => {
    const large =
      "https://images.example.test/photo,w=960.webp?signature=ab%2Fcd";
    const content = `<figure><img src="https://images.example.test/thumb.webp" srcset="https://images.example.test/small.webp 320w, ${large} 960w, https://images.example.test/huge.webp 4000w"><figcaption>Publisher credit</figcaption></figure>`;
    const entry = prepareEntry({ content });
    assert.equal(entry.coverSource, large);
    assert.equal(entry.content, content);
    assert.equal(
      prepareEntry({
        content:
          '<img src="https://example.test/thumb.jpg" srcset="https://example.test/thumb.jpg 160w, https://example.test/article.jpg 1280w">',
      }).coverSource,
      "https://example.test/article.jpg",
    );
    assert.equal(
      prepareEntry({
        content:
          '<img src="https://example.test/a.jpg" srcset="https://example.test/a.jpg 1x, https://example.test/b.jpg?sig=123 2x">',
      }).coverSource,
      "https://example.test/b.jpg?sig=123",
    );
    assert.equal(
      prepareEntry({
        content:
          '<img src="https://example.test/a.jpg" srcset="javascript:alert(1) 960w">',
      }).coverSource,
      "https://example.test/a.jpg",
    );
  });
  await test("Miniflux proxy images use publisher dimensions while keeping signed proxy URLs", () => {
    const small = proxy(
      "https://images.example.test/photo.avif?width=140&signature=small",
    );
    const large = proxy(
      "https://images.example.test/photo.avif?width=700&signature=large",
    );
    const entry = prepareEntry({
      enclosures: [{ url: small }, { url: large }],
    });
    assert.equal(entry.attachments.images.length, 2);
    assert.equal(entry.coverSource, large);
    const content = `<img src="${small}" srcset="${small} 140w, ${large} 700w">`;
    assert.equal(prepareEntry({ content }).coverSource, large);
  });
  await test("WebP and AVIF enclosures are images while audio, files and unsafe URLs retain handling", () => {
    const entry = prepareEntry({
      enclosures: [
        { url: "https://example.test/image.WEBP?sig=1" },
        {
          url: "https://example.test/image.avif?sig=2",
          mime_type: "application/octet-stream",
        },
        { url: "https://example.test/audio.mp3", mime_type: "audio/mpeg" },
        {
          url: "https://example.test/report.pdf",
          mime_type: "application/pdf",
        },
        { url: "javascript:alert(1)", mime_type: "image/png" },
      ],
    });
    assert.equal(entry.attachments.images.length, 2);
    assert.equal(entry.attachments.primaryMedia?.kind, "audio");
    assert.equal(entry.attachments.items[3]?.kind, "file");
    assert.equal(entry.attachments.items[4]?.canPreview, false);
  });
  await test("responsive inline images deduplicate enclosures even without declared dimensions", () => {
    const content =
      '<figure><img src="https://example.test/small.jpg" srcset="https://example.test/large.jpg 2x"><figcaption>Credit</figcaption></figure>';
    const entry = prepareEntry({
      content,
      enclosures: [
        { url: "https://example.test/large.jpg", mime_type: "image/jpeg" },
        { url: "https://example.test/new.avif" },
      ],
    });
    const model = buildArticleImageModel(
      entry.content,
      entry.attachments.items,
    );
    assert.equal(model.visibleAttachments.length, 1);
    assert.equal(
      model.visibleAttachments[0]?.url,
      "https://example.test/new.avif",
    );
    assert.equal(model.getImageIndex("https://example.test/large.jpg"), 0);
    assert.equal(model.getImageIndex("https://example.test/small.jpg"), 0);
    assert.equal(model.imageSlides[0]?.src, "https://example.test/large.jpg");
    assert.equal(model.visibleAttachments[0]?.galleryIndex, 1);
  });
  await test("image enclosures render accessible figures without a collapsed details wrapper", async () => {
    const module: unknown = await server.ssrLoadModule(
      "/src/components/Article/ArticleEnclosures.jsx",
    );
    function enclosureModule(
      value: unknown,
    ): value is { default: ComponentType<EnclosureProps> } {
      return defaultFunction(value);
    }
    assert.ok(enclosureModule(module));
    const Enclosures = module.default;
    const entry = prepareEntry({
      enclosures: [
        { url: "https://example.test/photo.avif" },
        { url: "https://example.test/report.pdf" },
      ],
    });
    const model = buildArticleImageModel("", entry.attachments.items);
    const html = renderToStaticMarkup(
      createElement(Enclosures, {
        items: model.visibleAttachments,
        onImagePreview: () => {},
        onOpenChange: () => {},
        open: false,
      }),
    );
    assert.match(html, /<figure/);
    assert.match(html, /<img/);
    assert.match(html, /<figcaption/);
    assert.match(html, /<button[^>]+aria-label=/);
    assert.ok(html.indexOf("</figure>") < html.indexOf("<details"));
    assert.match(html, /article_attachments.title 1/);
    assert.doesNotMatch(html, /<details[^>]+open/);
    assert.doesNotMatch(html, /<ul/);
  });
} finally {
  await server.close();
}
