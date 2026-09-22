`BlurPreview.png` uses the Apple website screenshot supplied by the user on September 22, 2026. The macOS strip and bottom browser status text were cropped out, and the image was reduced to 1512 pixels wide. The app applies its blur dynamically.

`BlurPreview.mp4` uses 251 browser frames captured while scrolling https://www.apple.com/ from the top to the footer on September 22, 2026. The capture used a 1152-by-748 desktop viewport matching the app preview's aspect ratio. Frames were timed evenly and interpolated for smooth motion, with short pauses at the ends; the return uses the captured sequence in reverse. The silent H.264 loop is 53.17 seconds, 920 by 598 pixels, at 24 frames per second. It includes only the webpage. Browser chrome, personal tabs, and desktop controls are excluded.

The app applies the current blur strength to decoded video frames. Playback pauses when the preview is hidden or the app is inactive. Reduce Motion uses the supplied still image.

The original website content belongs to Apple. `scripts/render-preview.swift` generates the older fictional notes alternative; it is not part of the build.
