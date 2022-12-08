local t = ...
local strDistId = t:get_platform()
local tResult = true

-- Copy the complete "lua" folder.
t:install('lua/', '${install_lua_path}/')

-- Copy the system script.
t:install('system.lua', '${install_base}')

-- Copy the complete "doc" folder.
t:install('doc/', '${build_doc}/')

-- Copy the wrapper.
if strDistId=='windows' then
  t:install('wrapper/windows/tester.bat',  '${install_executables}/')
elseif strDistId=='ubuntu' then
  t:install('wrapper/linux/tester',        '${install_executables}/')
else
  tResult = nil
end

return tResult
