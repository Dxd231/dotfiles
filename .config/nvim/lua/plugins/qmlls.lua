return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      qmlls = {
        cmd = { 
          "qmlls", 
          "-E", -- Telling the server to look for extra environment pathways
          "-I", "/usr/lib/qt6/qml" -- Direct look into Arch's Qt6 directory
        },
        filetypes = { "qml", "qmljs" },
      },
    },
  },
}
