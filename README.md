# BoxxyAuras

A World of Warcraft addon providing highly customizable display frames for player buffs and debuffs.

## Features

*   **Separate Buff & Debuff Frames:** Displays buffs and debuffs in independent frames.
*   **Draggable & Resizable:** Easily move and resize the buff and debuff frames to fit your UI layout.
*   **Configurable Columns:** Set the number of icons wide each frame should display via resize handles.
*   **Hold on Hover:** Auras remain visible (don't fade) while your mouse cursor is over the corresponding frame, making tooltips easier to read.
*   **Customizable Appearance:**
    *   Set individual icon sizes for buffs and debuffs.
    *   Choose Left, Center, or Right alignment for icons within each frame.
    *   Configure internal icon padding and spacing between icons (via config table in code).
*   **Lockable Frames:** Option to lock frames in place, hiding the background, border, title, and resize handles for a cleaner look.
*   **Smooth Animations:** Subtle animations play when auras are applied.
*   **Right-Click Cancellation:** Right-click your own buffs (when out of combat) to cancel them directly from the frame.
*   **Options Panel:** Configure settings easily using the `/ba` or `/boxxyauras` slash commands.

## Usage

*   **Options:** Type `/ba` or `/boxxyauras` in chat to open the options panel.
*   **Reset Frames:** Type `/ba reset` to reset the position and size of the buff and debuff frames to the default top-center location.
*   **Moving:** Unlock frames in the options panel, then click and drag the frame background.
*   **Resizing:** Unlock frames, then click and drag the left or right edge handles to change the number of columns.

## Installation

1.  Download the latest release ZIP file.
2.  Extract the `BoxxyAuras` folder into your `World of Warcraft/_retail_/Interface/AddOns/` directory.
3.  Ensure the addon is enabled in the character selection screen.

## Known Issues / Future Plans (Optional)

*   Right-click cancellation does not work while in combat due to Blizzard API restrictions.
*   (Add any other known quirks or planned features here)
