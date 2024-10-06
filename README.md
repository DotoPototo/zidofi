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

| Terminal         | OS                                   | FPS | Notes             | Date       | App Version |
| ---------------- | ------------------------------------ | --- | ----------------- | ---------- | ----------- |
| Windows Terminal | Windows 11 WSL2 (Ubuntu 22.04.5 LTS) | 220 |                   | 2024-10-02 | 0.1         |
| iTerm2           | Senoma 14.5                          | 72  |                   | 2024-10-02 | 0.1         |
| Terminal.app     | Senoma 14.5                          | N/A | Too slow to count | 2024-10-02 | 0.1         |

# TODO

- [ ] Improve error handling
- [x] Improve code structure / refactor
- [x] Update terminal size on resize

# Credits

This project was _heavily inspired_ by [DOOM-fire-zig](https://github.com/const-void/DOOM-fire-zig), which did not run on WSL so I decided to make my own project.

In addition, I also used the following resources:

- [Doom Fire Algorithm](https://github.com/filipedeschamps/doom-fire-algorithm)

- [Doom Fire JS Implementation](https://github.com/fabiensanglard/DoomFirePSX/tree/master)
