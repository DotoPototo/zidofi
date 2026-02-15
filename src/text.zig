const app = @import("main.zig");
const writers = @import("writers.zig");
const term = @import("term.zig");

pub fn testLigatures() !void {
    try term.resetScreen();
    try term.altScreenOn();
    try app.writeHeader();

    try writers.printCentered("Terminal ligatures and special characters test:\n\n");

    const ligature_tests = [_][]const u8{
        "┌──────────────────────────────┐\n",
        "│ Box Drawing                  │\n",
        "├──────────────────────────────┤\n",
        "│ ┌─┬┐  ┏━┳┓  ╔═╦╗  ╓─╥╖  ╒═╤╕ │\n",
        "│ │ ││  ┃ ┃┃  ║ ║║  ║ ║║  │ ││ │\n",
        "│ ├─┼┤  ┣━╋┫  ╠═╬╣  ╟─╫╢  ╞═╪╡ │\n",
        "│ │ ││  ┃ ┃┃  ║ ║║  ║ ║║  │ ││ │\n",
        "│ └─┴┘  ┗━┻┛  ╚═╩╝  ╙─╨╜  ╘═╧╛ │\n",
        "└──────────────────────────────┘\n\n",
        "Arrows and Symbols:\n",
        "← ↑ → ↓ ↔ ↕ ↖ ↗ ↘ ↙ ⇐ ⇑ ⇒ ⇓ ⇔ ⇕ ⇖ ⇗ ⇘ ⇙ ⇚ ⇛ ⇜ ⇝ ⇞ ⇟\n\n",
        "Programming Ligatures:\n",
        "== != === !== -> => >= <= << >> /* */ // ++ -- && || ?? ?. ??\n\n",
        "Math Symbols:\n",
        "∀ ∂ ∃ ∅ ∇ ∈ ∉ ∋ ∏ ∑ − ∕ ∗ ∙ √ ∝ ∞ ∠ ∧ ∨ ∩ ∪ ∫ ∴ ∼ ≅ ≈ ≠ ≡ ≤ ≥ ⊂ ⊃ ⊄ ⊆ ⊇ ⊕ ⊗ ⊥\n\n",
        "Miscellaneous Symbols:\n",
        "☀ ☁ ☂ ☃ ★ ☆ ☉ ☎ ☐ ☑ ☒ ☕ ☘ ☠ ☢ ☣ ☮ ☯ ☸ ☹ ☺ ☻ ☼ ☽ ☾ ♠ ♡ ♢ ♣ ♤ ♥ ♦ ♧ ♨ ♩ ♪ ♫ ♬ ♭ ♮ ♯\n\n",
        "Emoji:\n",
        "😀 😁 😂 😃 😄 😅 😆 😇 😈 😉 😊 😋 😌 😍 😎 😏 😐 😑 😒 😓 😔 😕 😖 😗 😘 😙 😚 😛 😜 😝 😞 😟 😠 😡 😢 😣 😤 😥 😦 😧 😨 😩 😪 😫 😬 😭 😮 😯 😰 😱 😲 😳 😴 😵 😶 😷 😸 😹 😺 😻 😼 😽 😾 😿 🙀 🙁 🙂 🙃 🙄 🙅 🙆 🙇 🙈 🙉 🙊 🙋 🙌 🙍 🙎 🙏\n\n",
        "Bold Text:\n",
        "𝗔𝗕𝗖𝗗𝗘𝗙𝗚𝗛𝗜𝗝𝗞𝗟𝗠𝗡𝗢𝗣𝗤𝗥𝗦𝗧𝗨𝗩𝗪𝗫𝗬𝗭\n\n",
        "Italic Text:\n",
        "𝘈𝘉𝘊𝘋𝘌𝘍𝘎𝘏𝘐𝘑𝘒𝘓𝘔𝘕𝘖𝘗𝘘𝘙𝘚𝘛𝘜𝘝𝘞𝘟𝘠𝘡\n\n",
    };

    for (ligature_tests) |ligtest| {
        try writers.writeBufferedFrame(ligtest);
    }
    try writers.flushWriterBuffer();

    if (app.shouldQuit()) return;
    try term.pressEnterToContinue();
}
