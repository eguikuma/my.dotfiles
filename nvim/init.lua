vim.opt.number = true
vim.opt.relativenumber = false
vim.opt.mouse = "a"
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.wrap = false
vim.opt.breakindent = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.autoindent = true
vim.opt.smartindent = true
vim.opt.clipboard = "unnamedplus"
vim.opt.splitbelow = true
vim.opt.splitright = true
vim.opt.termguicolors = true
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300
vim.opt.completeopt = "menuone,noselect"
vim.opt.undofile = true
vim.opt.signcolumn = "yes"
vim.opt.cursorline = true
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8

vim.g.mapleader = " "
vim.g.maplocalleader = " "

local keymap = vim.keymap.set
local opts = { noremap = true, silent = true }

keymap("n", "<C-s>", ":w<CR>", opts)
keymap("i", "<C-s>", "<Esc>:w<CR>a", opts)
keymap("n", "<C-a>", "ggVG", opts)
keymap("i", "<C-a>", "<Esc>ggVG", opts)

keymap("v", "<C-c>", '"+y', opts)
keymap("n", "<C-c>", '"+yy', opts)
keymap("i", "<C-v>", "<C-r>+", opts)
keymap("n", "<C-v>", '"+p', opts)
keymap("v", "<C-v>", '"+p', opts)
keymap("v", "<C-x>", '"+d', opts)
keymap("n", "<C-x>", '"+dd', opts)

keymap("n", "<C-z>", "u", opts)
keymap("i", "<C-z>", "<Esc>ua", opts)
keymap("n", "<C-y>", "<C-r>", opts)
keymap("i", "<C-y>", "<Esc><C-r>a", opts)

keymap("n", "<C-f>", "/", opts)
keymap("i", "<C-f>", "<Esc>/", opts)
keymap("n", "<C-h>", ":%s/", opts)

keymap("i", "<C-d>", "<Esc>dda", opts)
keymap("n", "<C-d>", "dd", opts)

keymap("n", "<S-Right>", "v<Right>", opts)
keymap("n", "<S-Left>", "v<Left>", opts)
keymap("n", "<S-Up>", "v<Up>", opts)
keymap("n", "<S-Down>", "v<Down>", opts)

keymap("v", "<S-Right>", "<Right>", opts)
keymap("v", "<S-Left>", "<Left>", opts)
keymap("v", "<S-Up>", "<Up>", opts)
keymap("v", "<S-Down>", "<Down>", opts)

keymap("n", "<C-S-Right>", "vw", opts)
keymap("n", "<C-S-Left>", "vb", opts)
keymap("v", "<C-S-Right>", "w", opts)
keymap("v", "<C-S-Left>", "b", opts)

keymap("n", "<C-l>", "V", opts)

require("plugins")
