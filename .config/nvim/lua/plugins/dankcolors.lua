return {
	{
		"RRethy/base16-nvim",
		priority = 1000,
		config = function()
			require('base16-colorscheme').setup({
				base00 = '#1a1110',
				base01 = '#1a1110',
				base02 = '#a59b99',
				base03 = '#a59b99',
				base04 = '#fff2ef',
				base05 = '#fff9f8',
				base06 = '#fff9f8',
				base07 = '#fff9f8',
				base08 = '#ffa19f',
				base09 = '#ffa19f',
				base0A = '#ffbfb2',
				base0B = '#b7ffa5',
				base0C = '#ffddd6',
				base0D = '#ffbfb2',
				base0E = '#ffcac0',
				base0F = '#ffcac0',
			})

			vim.api.nvim_set_hl(0, 'Visual', {
				bg = '#a59b99',
				fg = '#fff9f8',
				bold = true
			})
			vim.api.nvim_set_hl(0, 'Statusline', {
				bg = '#ffbfb2',
				fg = '#1a1110',
			})
			vim.api.nvim_set_hl(0, 'LineNr', { fg = '#a59b99' })
			vim.api.nvim_set_hl(0, 'CursorLineNr', { fg = '#ffddd6', bold = true })

			vim.api.nvim_set_hl(0, 'Statement', {
				fg = '#ffcac0',
				bold = true
			})
			vim.api.nvim_set_hl(0, 'Keyword', { link = 'Statement' })
			vim.api.nvim_set_hl(0, 'Repeat', { link = 'Statement' })
			vim.api.nvim_set_hl(0, 'Conditional', { link = 'Statement' })

			vim.api.nvim_set_hl(0, 'Function', {
				fg = '#ffbfb2',
				bold = true
			})
			vim.api.nvim_set_hl(0, 'Macro', {
				fg = '#ffbfb2',
				italic = true
			})
			vim.api.nvim_set_hl(0, '@function.macro', { link = 'Macro' })

			vim.api.nvim_set_hl(0, 'Type', {
				fg = '#ffddd6',
				bold = true,
				italic = true
			})
			vim.api.nvim_set_hl(0, 'Structure', { link = 'Type' })

			vim.api.nvim_set_hl(0, 'String', {
				fg = '#b7ffa5',
				italic = true
			})

			vim.api.nvim_set_hl(0, 'Operator', { fg = '#fff2ef' })
			vim.api.nvim_set_hl(0, 'Delimiter', { fg = '#fff2ef' })
			vim.api.nvim_set_hl(0, '@punctuation.bracket', { link = 'Delimiter' })
			vim.api.nvim_set_hl(0, '@punctuation.delimiter', { link = 'Delimiter' })

			vim.api.nvim_set_hl(0, 'Comment', {
				fg = '#a59b99',
				italic = true
			})

			local current_file_path = vim.fn.stdpath("config") .. "/lua/plugins/dankcolors.lua"
			if not _G._matugen_theme_watcher then
				local uv = vim.uv or vim.loop
				_G._matugen_theme_watcher = uv.new_fs_event()
				_G._matugen_theme_watcher:start(current_file_path, {}, vim.schedule_wrap(function()
					local new_spec = dofile(current_file_path)
					if new_spec and new_spec[1] and new_spec[1].config then
						new_spec[1].config()
						print("Theme reload")
					end
				end))
			end
		end
	}
}
