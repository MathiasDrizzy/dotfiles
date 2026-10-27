# dotbar

A native macOS menu-bar replacement written in Swift (AppKit, no third-party dependencies), built to sit on top of the system menu bar next to [AeroSpace](https://github.com/nikitabobko/AeroSpace): workspaces, the front app, weather, battery, clock, Control Center and more, with a very small CPU and memory footprint.

```sh
scripts/bundle.sh ~/Applications     # builds dotbar.app (signed with a local certificate when one exists)
swift run dotbar-tests               # the tests
```

Started at login by a launch agent that [dotfiles](https://github.com/MathiasDrizzy/dotfiles) installs. First run asks for Location (the weather box) and Accessibility (menus, Control Center) in System Settings.

`DotbarCore` holds the pure logic (formatting, state machines, parsing) with the tests; `dotbar` is the AppKit shell.
