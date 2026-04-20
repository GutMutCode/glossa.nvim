if vim.g.loaded_glossa_nvim == 1 then
  return
end

vim.g.loaded_glossa_nvim = 1

require("glossa").register()
