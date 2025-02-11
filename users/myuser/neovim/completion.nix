{
  programs.nixvim = {
    plugins = {
      luasnip = {
        enable = true;
        extraConfig = {
          history = true;
          # Update dynamic snippets while typing
          updateevents = "TextChanged,TextChangedI";
          enable_autosnippets = true;
        };
      };

      cmp_luasnip.enable = true;
      cmp-cmdline.enable = true;
      cmp-cmdline-history.enable = true;
      cmp-path.enable = true;
      cmp-emoji.enable = true;
      cmp-treesitter.enable = true;
      cmp-nvim-lsp.enable = true;
      cmp-nvim-lsp-document-symbol.enable = true;
      cmp-nvim-lsp-signature-help.enable = true;
      nvim-cmp = {
        enable = true;
        sources = [
          {name = "nvim_lsp_signature_help";}
          {name = "nvim_lsp";}
          {name = "nvim_lsp_document_symbol";}
          {name = "path";}
          {name = "treesitter";}
          {name = "luasnip";}
          {name = "emoji";}
        ];
        mappingPresets = ["insert"];
        mapping = {
          "<CR>" = ''
            cmp.mapping.confirm({
              behavior = cmp.ConfirmBehavior.Replace,
              select = false,
            })
          '';
          "<C-d>" = "cmp.mapping.scroll_docs(-4)";
          "<C-f>" = "cmp.mapping.scroll_docs(4)";
          "<C-e>" = "cmp.mapping.abort()";
          "<Tab>" = {
            modes = ["i" "s"];
            action = ''
              function(fallback)
              local has_words_before = function()
                local line, col = table.unpack(vim.api.nvim_win_get_cursor(0))
                return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match "%s" == nil
              end

              if cmp.visible() then
                cmp.select_next_item()
              elseif require("luasnip").expandable() then
                require("luasnip").expand()
              elseif require("luasnip").expand_or_locally_jumpable() then
                require("luasnip").expand_or_jump()
              elseif has_words_before() then
                cmp.complete()
              else
                fallback()
              end
              end
            '';
          };
          "<S-Tab>" = {
            modes = ["i" "s"];
            action = ''
              function(fallback)
              if cmp.visible() then
                cmp.select_prev_item()
              elseif luasnip.jumpable(-1) then
                luasnip.jump(-1)
              else
                fallback()
              end
              end
            '';
          };
        };
        formatting.fields = ["abbr" "kind" "menu"];
        formatting.format = ''
          function(_, vim_item)
          local icons = {
            Namespace = "󰌗",
            Text = "󰉿",
            Method = "󰆧",
            Function = "󰆧",
            Constructor = "",
            Field = "󰜢",
            Variable = "󰀫",
            Class = "󰠱",
            Interface = "",
            Module = "",
            Property = "󰜢",
            Unit = "󰑭",
            Value = "󰎠",
            Enum = "",
            Keyword = "󰌋",
            Snippet = "",
            Color = "󰏘",
            File = "󰈚",
            Reference = "󰈇",
            Folder = "󰉋",
            EnumMember = "",
            Constant = "󰏿",
            Struct = "󰙅",
            Event = "",
            Operator = "󰆕",
            TypeParameter = "󰊄",
            Table = "",
            Object = "󰅩",
            Tag = "",
            Array = "󰅪",
            Boolean = "",
            Number = "",
            Null = "󰟢",
            String = "󰉿",
            Calendar = "",
            Watch = "󰥔",
            Package = "",
            Copilot = "",
            Codeium = "",
            TabNine = "",
          }
          vim_item.kind = string.format("%s %s", icons[vim_item.kind], vim_item.kind)
          return vim_item
          end
        '';
        snippet.expand = "luasnip";
      };

      # TODO use "ray-x/lsp_signature.nvim"
    };

    extraConfigLuaPost = ''
      local cmp = require "cmp"
      cmp.setup.cmdline(":", {
        mapping = cmp.mapping.preset.cmdline(),
        sources = {
          { name = "cmdline" },
          { name = "cmp-cmdline-history" },
        },
      })
    '';
  };
}
