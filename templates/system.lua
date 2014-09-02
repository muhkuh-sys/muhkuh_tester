require("muhkuh_cli_init")
require("test_system")

-- This is a list of all available test cases in this test suite.
-- The test cases are specified by a number starting at 1.
local auiTestCases = {
	1,
	2,
	3,
	4
}


local fTestResult = test_system.run(arg, auiTestCases)
if fTestResult==true then
	print("OK!")
elseif fTestResult==false then
	error("The test suite failed!")
end
