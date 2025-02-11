{
  lib,
  pkgs,
  ...
}: {
  programs.nixvim.plugins = {
    lsp = {
      enable = true;
      preConfig = ''
        local lsp_symbol = function(name, icon)
        vim.fn.sign_define(
          "DiagnosticSign" .. name,
          { text = icon, numhl = "Diagnostic" .. name, texthl = "Diagnostic" .. name }
        )
        end

        lsp_symbol("Error", "󰅙")
        lsp_symbol("Info", "")
        lsp_symbol("Hint", "󰌵")
        lsp_symbol("Warn", "")
      '';
      servers = {
        bashls.enable = true;
        cssls.enable = true;
        html.enable = true;
        lua-ls.enable = true;
        rust-analyzer = {
          enable = true;
          settings = {
            checkOnSave = true;
            check.command = "clippy";
          };
          # cargo and rustc are managed per project with their own flakes.
          installCargo = false;
          installRustc = false;
        };
        nil_ls = {
          enable = true;
          settings = {
            formatting.command = [(lib.getExe pkgs.alejandra) "--quiet"];
          };
        };
        nixd.enable = true;
      };

      #keymaps = {
      #  diagnostic = {
      #    "<leader>k" = "goto_prev";
      #    "<leader>j" = "goto_next";
      #  };
      #  lspBuf = {
      #    "gd" = "definition";
      #    "gD" = "references";
      #    "<leader>lt" = "type_definition";
      #    "gi" = "implementation";
      #    "K" = "hover";
      #    "<leader>k" = "hover";
      #    "<leader>r" = "rename";
      #  };
      #};
    };

    none-ls = {
      enable = true;
      sources = {
        code_actions = {
          # gitsigns.enable = true;
          shellcheck.enable = true;
        };
        diagnostics = {
          deadnix.enable = true;
          gitlint.enable = true;
          luacheck.enable = true;
          protolint.enable = true;
          shellcheck.enable = true;
        };
        formatting = {
          alejandra.enable = true;
          jq.enable = true;
          markdownlint.enable = true;
          rustfmt.enable = true;
          sqlfluff.enable = true;
          shfmt.enable = true;
          stylua.enable = true;
        };
      };
    };

    # TODO dap.enable = true;
  };
}
