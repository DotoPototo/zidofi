# ZiDoFi

```
███████╗██╗██████╗  ██████╗ ███████╗██╗
╚══███╔╝██║██╔══██╗██╔═══██╗██╔════╝██║
  ███╔╝ ██║██║  ██║██║   ██║█████╗  ██║
 ███╔╝  ██║██║  ██║██║   ██║██╔══╝  ██║
███████╗██║██████╔╝╚██████╔╝██║     ██║
╚══════╝╚═╝╚═════╝  ╚═════╝ ╚═╝     ╚═╝
```

**Zi**g **Do**om **Fi**re

This is my **second** project in Zig, _ever_.

My first project was `Hello World`.

---

# Test Your TTY

Test your terminal with this simple program that

- Prints colours and gradients
- Prints ligatures, symbols and emojis
- Runs a Doom Fire simulation

![Doom Fire](./.github/doom-fire.gif)

# Installation

Clone this repository and run the following command:

```bash
zig build -Doptimize=ReleaseFast run
```

For endless fire, append the `-- --endless` flag:

```bash
zig build -Doptimize=ReleaseFast run -- --endless
```

# Doom Fire Results

Results are for terminal size 160x48 after running 666 frames of the Doom Fire simulation.

| Terminal         | OS                                   | FPS | Notes             | Date       | App Version | Zig Version |
| ---------------- | ------------------------------------ | --- | ----------------- | ---------- | ----------- | ----------- |
| Windows Terminal | Windows 11 WSL2 (Ubuntu 22.04.5 LTS) | 240 |                   | 2024-10-02 | 0.0.1       | 0.13.0      |
| Windows Terminal | Windows 11 WSL2 (Ubuntu 24.04.3 LTS) | 165 |                   | 2025-09-23 | 0.0.2       | 0.15.1      |
| iTerm2           | Senoma 14.5                          | 57  |                   | 2024-10-02 | 0.0.1       | 0.13.0      |
| Terminal.app     | Senoma 14.5                          | N/A | Too slow to count | 2024-10-02 | 0.0.1       | 0.13.0      |

# TODO

- [x] Add memory usage to output
- [x] Add windows support
- [x] Improve code structure / refactor
- [x] Update terminal size on resize
- [ ] Improve error handling

# Credits

This project was _heavily inspired_ by [DOOM-fire-zig](https://github.com/const-void/DOOM-fire-zig), which did not run on WSL so I decided to make my own project.

In addition, I also used the following resources:

- [Doom Fire Algorithm](https://github.com/filipedeschamps/doom-fire-algorithm)

- [Doom Fire JS Implementation](https://github.com/fabiensanglard/DoomFirePSX/tree/master)
