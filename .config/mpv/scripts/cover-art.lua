local utils = require 'mp.utils'

local function run_bash_script()
    -- 1. Grab the path of the currently loaded file
    local path = mp.get_property("path")
    
    -- 2. Ensure a file is actually loaded
    if not path then return end
    
    -- 3. Execute the script in a detached background process
    utils.subprocess_detached({
        args = { "/home/niconico/.config/mpv/cover-art.sh", path }
    })
end

-- Hook into the file-loaded event (fires right after a video successfully loads)
mp.register_event("file-loaded", run_bash_script)mp.register_event("file-loaded", generate_thumbnail)
