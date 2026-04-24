<p align="center">
  <img src="assets/glossa.png" alt="glossa.nvim banner">
</p>

# glossa.nvim

Minimal Neovim scaffold for a language-learning plugin inspired by the lookup flow of `vim-translator`.

This first version is intentionally small:

- capture the current word, visual selection, range, or explicit text
- display the result in a floating window
- replace the current word or selection with a translation
- save the last lookup result as a study card
- open a due-card review list

The default provider is the public Google Translate endpoint used by `vim-translator`.
The bundled `mock` provider is still available for local UI and storage testing.

## Layout

```text
glossa.nvim/
├─ assets/glossa.png
├─ plugin/glossa.lua
├─ lua/glossa/init.lua
├─ lua/glossa/lookup.lua
├─ lua/glossa/providers/google.lua
├─ lua/glossa/providers/mock.lua
├─ lua/glossa/review.lua
├─ lua/glossa/store.lua
├─ lua/glossa/window.lua
└─ doc/glossa.txt
```

## Local Development

Using `lazy.nvim`:

```lua
{
  dir = "~/devs/repos/personal/glossa.nvim",
  config = function()
    require("glossa").setup({
      lookup = {
        source_lang = "en",
        target_lang = "ko",
      },
      replace = {
        source_lang = "ja",
        target_lang = "en",
      },
    })
  end,
}
```

Direct runtimepath test:

```vim
:set rtp+=~/devs/repos/personal/glossa.nvim
:GlossaLookup hello
```

## Commands

- `:GlossaLookup [text]`
- `:'<,'>GlossaLookup`
- `:GlossaReplace [text]`
- `:'<,'>GlossaReplace`
- `:GlossaSave`
- `:GlossaReview`
- `:GlossaStats`

## Plug Mappings

No default keymaps are installed. Suggested mappings:

```lua
vim.keymap.set("n", "<leader>gl", "<Plug>(GlossaLookup)")
vim.keymap.set("x", "<leader>gl", "<Plug>(GlossaLookup)")
vim.keymap.set("n", "<leader>gR", "<Plug>(GlossaReplace)")
vim.keymap.set("x", "<leader>gR", "<Plug>(GlossaReplace)")
vim.keymap.set("n", "<leader>gs", "<Plug>(GlossaSave)")
vim.keymap.set("n", "<leader>gr", "<Plug>(GlossaReview)")
vim.keymap.set("n", "<leader>gt", "<Plug>(GlossaStats)")
```

## Configuration

```lua
require("glossa").setup({
  provider = "google",
  data_file = vim.fn.stdpath("data") .. "/glossa.nvim/cards.json",
  lookup = {
    source_lang = "en",
    target_lang = "ko",
  },
  replace = {
    source_lang = "ja",
    target_lang = "en",
  },
  google = {
    endpoint = "https://translate.googleapis.com/translate_a/single",
    timeout_ms = 8000,
  },
  window = {
    border = "rounded",
    max_width = 0.55,
    max_height = 0.6,
  },
})
```

`lookup` controls popup translations.

`replace` controls `:GlossaReplace` and `<Plug>(GlossaReplace)`, which replace the current word, range, or visual selection directly in the buffer.

## Next Step

Current backend notes:

- `google` uses the same public endpoint style as `vim-translator`
- it requires `curl` in your `PATH`
- it is not an official Google Cloud API and may change without notice
- `mock` is still available when you want to test UI or storage without network access

The current code already has the flow you need:

`lookup -> float -> save -> review`
