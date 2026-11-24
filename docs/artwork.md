# Artwork

Each game can have four images:

| Kind | Shape | Used for |
|---|---|---|
| `cover` | Portrait, 2:3 (600×900) | Cards in rows, grids and search |
| `hero` | Wide background | The billboard, and the 16:9 Favorites cards (cropped to 16:9) |
| `logo` | Transparent title logo | Shown over the hero on the billboard and on Favorites cards |
| `icon` | Square, 256 px | Generated fallback cards when there is no cover |

The billboard's slideshow shows every game: its `hero`, else its wide header, else a blurred version of its cover or icon. Game Hub's own artwork (its logo, icons and banner) is separate: see [`www/brand`](../www/brand/README.md).

## Priority

For each kind, the first image that exists is used:

1. **Your upload:** `data\covers\<id>-<kind>.custom.<ext>`
2. **Downloaded store art:** `data\covers\<id>-<kind>.<ext>`
3. **Steam's local library cache** (Steam games only), copied by the scanner into `data\art\`

If none exists, the card is drawn from the game's icon: a blurred icon background with the icon and the name on top. Without an icon, it shows the initials on a neutral background.

On Favorites cards:

- the logo is laid over the hero only when the hero comes from a source that has no title in it;
- Steam's wide *header* image, which already contains the title, is used as a fallback.

## Automatic download

[`fetch-covers.ps1`](../fetch-covers.ps1) runs after every scan, or from **Settings › Fetch missing covers**. It looks at games that have no cover yet, skipping those marked `noArt`, and tries these sources in order:

**1. Steam**

- The app id comes from, in order:
  - a `steamAppId` override;
  - the Steam game's own id;
  - an **exact title match** on the Steam store. Titles are compared lower-case, with only letters and digits kept and trademark symbols dropped.
- A near match is never used: a wrong cover is worse than none.
- The asset list comes from Steam's store API (`IStoreBrowseService/GetItems`). It downloads:
  - the 600×900 capsule;
  - the library hero;
  - the logo.
- If the asset list has nothing, it falls back to Steam's classic image URLs.

**2. Microsoft Store**

- Used for Xbox app games (their Store id comes from the game itself) and for games with an `msStoreId` override.
- Reads the product from the public display catalog and downloads:
  - the *Poster* (or *BoxArt*) as the cover;
  - the *SuperHeroArt* (or *TitledHeroArt*) as the hero.

**3. Epic Games**

- For Epic installs, it reads the catalog ids from the Epic launcher manifest or the game's own `.egstore` folder.
- It looks them up in the Epic launcher's **local** catalog cache (`%ProgramData%\Epic\EpicGamesLauncher\Data\Catalog\catcache.bin`), which already lists the official key-art URLs.
- It downloads:
  - *DieselGameBoxTall* as the cover;
  - *DieselGameBox* as the hero;
  - *DieselGameBoxLogo* as the logo.

Games no source could cover are recorded in `data\covers\_misses.json` with the date, so they aren't searched again on every scan.

- **Retry all of them:** run `fetch-covers.ps1 -Force`. This re-downloads artwork for every game too.
- **Retry a single game:** delete its entry from `_misses.json`, or give it artwork by hand.

Every downloaded file is checked by its first bytes and must be a real JPEG, PNG or WebP. Anything else, such as an HTML error page, is discarded.

## Setting artwork by hand

Use the pen on a game's card:

- **Search Steam artwork.** Pick the right Steam page when the automatic match failed or picked an edition you don't want. The choice is saved as `steamAppId`, so it survives rescans. It also replaces any custom cover or background.
- **Upload cover… / Upload background…** Use any JPEG, PNG or WebP up to 25 MB. You can also drop an image file onto the cover preview.
- **Remove custom cover / background.** Goes back to the store art.

Xbox app games get their Store id automatically. For other Microsoft Store games, set `msStoreId` in `overrides.json` and run **Fetch missing covers**. To keep a game on its generated card, set `noArt: true`.

## Network calls

Artwork is the only reason Game Hub goes online. All requests use the user agent `GameHub/1.0` and carry only a game title or a store id.

| Request | Host | Sends |
|---|---|---|
| Steam store search | `store.steampowered.com/api/storesearch` | The game title |
| Steam asset list | `api.steampowered.com/IStoreBrowseService/GetItems` | Steam app ids |
| Steam images | `shared.akamai.steamstatic.com`, `cdn.cloudflare.steamstatic.com` | Image paths |
| Microsoft Store catalog | `displaycatalog.mp.microsoft.com` | The `msStoreId` you set, or an Xbox app game's Store id |
| Microsoft Store images | Image hosts named in the catalog response | Image paths |
| Epic images | Image hosts named in Epic's local catalog cache | Image paths |

The Steam search in the edit dialog also shows small result thumbnails. Your browser loads those directly from Steam's image CDN.
