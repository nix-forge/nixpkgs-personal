type SpotifyUri = { type: string; id: string };
type MenuPredicate = (uris: unknown) => boolean;

declare const Spicetify: {
  Events: { webpackLoaded: { on(callback: () => void): void } };
  ContextMenu?: {
    Item: new (
      name: string,
      onClick: (uris: unknown) => void | Promise<void>,
      shouldAdd: MenuPredicate,
    ) => unknown;
    SubMenu: new (
      name: string,
      items: unknown[],
      shouldAdd: MenuPredicate,
    ) => { register(): void };
  };
  CosmosAsync?: { get(url: string): Promise<unknown> };
  URI?: {
    Type: { TRACK: string };
    fromString(uri: string): SpotifyUri | null;
  };
  showNotification(message: string): void;
};

(() => {
  function name(value: unknown): string | undefined {
    return value !== null &&
      typeof value === "object" &&
      "name" in value &&
      typeof value.name === "string"
      ? value.name
      : undefined;
  }

  function firstArtistName(value: unknown): string | undefined {
    return value !== null &&
      typeof value === "object" &&
      "artists" in value &&
      Array.isArray(value.artists)
      ? name(value.artists[0])
      : undefined;
  }

  function album(value: unknown): unknown {
    return value !== null && typeof value === "object" && "album" in value
      ? value.album
      : undefined;
  }

  function selectedTrackId(uris: unknown): string | null {
    if (
      !Array.isArray(uris) ||
      uris.length !== 1 ||
      typeof uris[0] !== "string"
    ) {
      return null;
    }
    const URI = Spicetify.URI;
    if (!URI) return null;
    try {
      const selected = URI.fromString(uris[0]);
      return selected?.type === URI.Type.TRACK ? selected.id : null;
    } catch {
      return null;
    }
  }

  async function openMusicBrainzSearch(
    uris: unknown,
    type: "recording" | "release" | "artist",
    fields: (track: unknown) => Array<string | undefined>,
  ): Promise<void> {
    const id = selectedTrackId(uris);
    if (!id) return;

    try {
      const CosmosAsync = Spicetify.CosmosAsync;
      if (!CosmosAsync) throw new Error("Spotify lookup API is unavailable");
      const track = await CosmosAsync.get(
        `https://api.spotify.com/v1/tracks/${encodeURIComponent(id)}`,
      );
      const query = fields(track).filter(Boolean).join(" ");
      if (!query) throw new Error("Spotify returned no searchable metadata");

      const url = new URL("https://musicbrainz.org/search");
      url.searchParams.set("type", type);
      url.searchParams.set("query", query);
      window.open(url.toString(), "_blank", "noopener,noreferrer");
    } catch (error) {
      console.warn("MetaBrainz lookup failed", error);
      Spicetify.showNotification("Could not look up this track on MusicBrainz");
    }
  }

  const trackOnly: MenuPredicate = (uris) => selectedTrackId(uris) !== null;

  let menuRegistered = false;
  function initMetaBrainz() {
    if (menuRegistered) return;
    const { ContextMenu } = Spicetify;
    if (!ContextMenu) {
      console.warn("MetaBrainz context menu API is unavailable");
      return;
    }

    const searchItem = (
      label: string,
      type: "recording" | "release" | "artist",
      fields: (track: unknown) => Array<string | undefined>,
    ): unknown =>
      new ContextMenu.Item(
        label,
        (uris) => openMusicBrainzSearch(uris, type, fields),
        trackOnly,
      );

    new ContextMenu.SubMenu(
      "MetaBrainz",
      [
        searchItem("Find recording on MusicBrainz", "recording", (track) => [
          name(track),
          firstArtistName(track),
        ]),
        searchItem("Find release on MusicBrainz", "release", (track) => [
          name(album(track)),
          firstArtistName(album(track)) || firstArtistName(track),
        ]),
        searchItem("Find artist on MusicBrainz", "artist", (track) => [
          firstArtistName(track),
        ]),
        new ContextMenu.Item(
          "Connect Spotify to ListenBrainz",
          () => {
            window.open(
              "https://listenbrainz.org/settings/music-services/details/",
              "_blank",
              "noopener,noreferrer",
            );
          },
          trackOnly,
        ),
      ],
      trackOnly,
    ).register();
    menuRegistered = true;
  }

  // The wrapper replays this event for extensions loaded after webpack startup.
  // URI and CosmosAsync initialize independently; inspect them at interaction time.
  Spicetify.Events.webpackLoaded.on(initMetaBrainz);
})();
