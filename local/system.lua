require 'muhkuh_cli_init'
local tTestSystem = require 'test_system'()
local iResult = tTestSystem:run()
os.exit(iResult, true)
