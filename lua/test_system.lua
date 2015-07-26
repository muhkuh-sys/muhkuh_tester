module("test_system", package.seeall)

------------------------------------------------------------------------------


-- The "show parameter" mode is disabled by default.
local fShowParameters = false

-- No log file.
local tLogFile = nil

-- Parameters for all modules.
local atAllParameters = {}

-- Run over all available test cases and get the test modules.
local aModules = {}

-- This list collects all parameters from the CLI. They are not split into their components.
local astrRawParameters = {}

-- This list collects all test cases to run.
local auiTests = {}

-- This is the filename of the log file.
local strLogFileName = nil

-- This is the pattern for the interface.
local strInterfacePattern = nil


------------------------------------------------------------------------------


local function collect_testcases(auiTestCases)
	for iCnt,uiTestCase in ipairs(auiTestCases) do
		-- Does a test with this number already exist?
		if aModules[uiTestCase]~=nil then
			error(string.format("More than one test with the index %d exists!", uiTestCase))
		end
		
		-- Create the filename for the test case.
		strTestCaseFilename = string.format("test%02d", uiTestCase)
		
		-- Load the test case.
		local tModule = require(strTestCaseFilename)
		aModules[uiTestCase] = tModule
	end
end


local function print_aligned(aLines, strFormat)
	-- Get the maximum size of the lines.
	local sizLineMax = 0
	for iCnt,aLine in ipairs(aLines) do
		local sizLine = string.len(aLine[1])
		sizLineMax = math.max(sizLineMax, sizLine)
	end
	
	-- Print all strings with the appropriate fillup.
	for iCnt,aLine in ipairs(aLines) do
		local sizFillup = sizLineMax - string.len(aLine[1])
		local astrTexts = aLine[2]
		print(string.format(strFormat, aLine[1] .. string.rep(" ", sizFillup), astrTexts[1]))
		for iLineCnt=2,#astrTexts,1 do
			print(string.format(strFormat, string.rep(" ", sizLineMax), astrTexts[iLineCnt]))
		end
	end
end



local function show_all_parameters()
	print("All parameters:")
	print("")
	for uiTestCase,tModule in ipairs(aModules) do
		local strTestName = tModule.CFG_strTestName
		print(string.format("  Test case %02d: '%s'", uiTestCase, strTestName))
		
		local atPrint = {}
		for iCnt1,tParameter in ipairs(tModule.CFG_aParameterDefinitions) do
			if tParameter.default==nil then
				strDefault = "no default value"
			else
				strDefault = string.format("default: %s", tParameter.default)
			end
			table.insert(atPrint, { string.format("%02d:%s", uiTestCase, tParameter.name), {tParameter.help, strDefault}})
		end
		print_aligned(atPrint, "    %s  %s")
		print("")
	end
end



local function get_module_index(strModuleName)
	iResult = nil
	
	-- Loop over all available modules.
	for iCnt,tModule in ipairs(aModules) do
		if tModule.CFG_strTestName==strModuleName then
			iResult = iCnt
			break
		end
	end
	
	return iResult
end



local function find_parameter(tModule, strParameterName)
	tResult = nil
	
	for iCnt,tParameter in ipairs(tModule.CFG_aParameterDefinitions) do
		if tParameter.name==strParameterName then
			tResult = tParameter
			break
		end
	end
	
	return tResult
end



local function show_parameters(uiTestCase)
	-- Get the parameters for the test case.
	local atModuleParameter = atAllParameters[uiTestCase]
	if atModuleParameter==nil then
		print(string.format("No parameters Invalid test case index %d!", uiTestCase))
	else
		-- Show all parameters for the module.
		for strParameterName,strParameterValue in pairs(atModuleParameter) do
			print(string.format("  %02d:%s = %s", uiTestCase, strParameterName, strParameterValue))
		end
	end
end


--[[
local function show_all_parameters()
	-- Show all parameter.
	print("All collected parameters:")
	for uiTestCase,atModuleParameter in pairs(atAllParameters) do
		for strParameterName,strParameterValue in pairs(atModuleParameter) do
			print(string.format("  %02d:%s = %s", uiTestCase, strParameterName, strParameterValue))
		end
		print("")
	end
end
--]]


local function logfile_print(...)
	print_original(...)
	if tLogFile~=nil then
		if type(...)=="string" then
			tLogFile:write(...)
			tLogFile:write("\n")
		elseif type(...)=="table" then
			for iCnt,strLine in ipairs(...) do
				tLogFile:write(strLine)
				tLogFile:write("\n")
			end
		else
			tLogFile:write(tostring(strLine))
			tLogFile:write("\n")
		end
	end
end



local function logfile_print_raw(...)
	io.write(...)
	if tLogFile~=nil then
		tLogFile:write(...)
	end
end



local function parse_commandline_arguments(astrArg, auiAllTestCases)
	-- Parse all command line arguments.
	sizArgCnt = 1
	sizArgMax = #astrArg
	while sizArgCnt<=sizArgMax do
		strArg = astrArg[sizArgCnt]
		if strArg=="-l" or strArg=="--logfile" then
			sizArgCnt = sizArgCnt + 1
			if sizArgCnt>sizArgMax then
				error(string.format("Missing argument for %s !", strArg))
			end
			if strLogFileName~=nil then
				print("Warning: multiple definitions for the log file. Disacrding old value!")
			end
			strLogFileName = astrArg[sizArgCnt]
		elseif strArg=="-i" or strArg=="--interface" then
			sizArgCnt = sizArgCnt + 1
			if sizArgCnt>sizArgMax then
				error(string.format("Missing argument for %s !", strArg))
			end
			if strInterfacePattern~=nil then
				print("Warning: multiple definitions for the interface. Disacrding old value!")
			end
			strInterfacePattern = astrArg[sizArgCnt]
		elseif strArg=="--show-parameters" then
			fShowParameters = true
		elseif strArg=="-p" or strArg=="--parameter" then
			sizArgCnt = sizArgCnt + 1
			if sizArgCnt>sizArgMax then
				error(string.format("Missing argument for %s !", strArg))
			end
			-- Add the argument to the list of parameters.
			strArg = astrArg[sizArgCnt]
			tMatch = string.match(strArg, "([0-9a-zA-Z_]+):([0-9a-zA-Z_]+)=(.*)")
			if tMatch==nil then
				error(string.format("The parameter definition has an invalid format: '%s'", strArg))
			end
			table.insert(astrRawParameters, strArg)
		elseif strArg=="-P" or strArg=="--parameter-file" then
			sizArgCnt = sizArgCnt + 1
			if sizArgCnt>sizArgMax then
				error(string.format("Missing argument for %s !", strArg))
			end
			-- Add the argument to the list of parameters.
			strArg = astrArg[sizArgCnt]
			table.insert(astrRawParameters, "@" .. strArg)
		else
			uiTestCase = tonumber(strArg)
			if uiTestCase==nil then
				error(string.format("The parameter '%s' must be a test number, but it is no number.", strArg))
			end
			table.insert(auiTests, uiTestCase)
		end
		
		sizArgCnt = sizArgCnt + 1
	end
	
	if fShowParameters==false then
		-- The interface parameter is mandatory.
		if strInterfacePattern==nil then
			error("No interface specified!")
		end
	end
	
	-- If no test cases were specified run all of them.
	if #auiTests==0 then
		auiTests = auiAllTestCases
	end
end



local function process_one_parameter(atParameters, strParameterLine)
	-- Ignore end of file markers.
	if strParameterLine==nil then
		-- Ignore end of file markers.
	-- Ignore empty lines.
	elseif string.len(strParameterLine)==0 then
		-- Ignore empty lines.
	-- Ignore lines starting with a '#'. This is used in parameter files.
	elseif string.sub(strParameterLine, 1, 1)=="#" then
		-- Ignore comments.
	-- This is a parameter file if the entry starts with "@".
	elseif string.sub(strParameterLine, 1, 1)=="@" then
		-- Get the filename without the '@'.
		local strFilename = string.sub(strParameterLine, 2)
		print ("Processing file ", strFilename)
		-- Iterate over all lines.
		for strLine in io.lines(strFilename) do
			if strLine~=nil then
				process_one_parameter(atParameters, strLine)
			end
		end
	else
		strTestCase,strParameterName,strValue = string.match(strParameterLine, "([0-9]+):([0-9a-zA-Z_]+)=(.*)")
		if strTestCase==nil or strParameterName==nil or strValue==nil then
			strTestCase,strParameterName,strValue = string.match(strParameterLine, "([0-9a-zA-Z_]+):([0-9a-zA-Z_]+)=(.*)")
			if strTestCase==nil or strParameterName==nil or strValue==nil then
				error(string.format("The parameter definition has an invalid format: '%s'", strParameterLine))
			else
				uiTestCase = get_module_index(strTestCase)
			end
		else
			uiTestCase = tonumber(strTestCase)
		end
		
		tModule = aModules[uiTestCase]
		if tModule==nil then
			error(string.format("Module '%d' not found!", uiTestCase))
		end
		
		tParameter = find_parameter(tModule, strParameterName)
		if tParameter==nil then
			error(string.format("The module '%d' has no parameter '%s'!", uiTestCase, strParameterName))
		end
		
		-- Add the parameter to the array.
		if atAllParameters[uiTestCase]==nil then
			atParameters[uiTestCase] = {}
		end
		local atModuleParameter = atParameters[uiTestCase]
		atModuleParameter[strParameterName] = strValue
	end
end



local function collect_parameters()
	-- Expand all file entries recursively.
	
	-- Collect all default parameter.
	for uiTestCase,tModule in ipairs(aModules) do
		local strTestName = tModule.CFG_strTestName
		
		local atParameters = {}
		for iCnt1,tParameter in ipairs(tModule.CFG_aParameterDefinitions) do
			atParameters[tParameter.name] = tParameter.default
		end
		
		atAllParameters[uiTestCase] = atParameters
	end
	
	-- Process all parameters.
	for iCnt,strParameter in ipairs(astrRawParameters) do
		process_one_parameter(atAllParameters, strParameter)
	end
end



local function check_parameters()
	-- Check all parameters.
	local fParametersOk = true
	for uiTestCase,tModule in ipairs(aModules) do
		-- Get the parameters for the module.
		local atParameters = atAllParameters[uiTestCase]
		
		for iCntParameter,tParameter in ipairs(tModule.CFG_aParameterDefinitions) do
			-- Does the parameter exist?
			local tValue = atParameters[tParameter.name]
			if tValue==nil then
				-- The parameter does not exist. Is it mandatory?
				if tParameter.mandatory==true then
					-- Yes, it is mandatory. That's an error.
					print(string.format("The mandatory parameter %02d:%s is missing.", uiTestCase, tParameter.name))
					fParametersOk = false
				end
			else
				-- The parameter exists. Check the value if a validate function exists.
				if tParameter.validate~=nil then
					fValid,strError = tParameter.validate(tValue, tParameter.constrains)
					if fValid==false then
						print(string.format("The parameter %02d:%s is invalid: %s", uiTestCase, tParameter.name, strError))
						fParametersOk = false
					end
				end
			end
		end
	end
	if fParametersOk==false then
		error("Some parameters were invalid. Not running the tests!")
	end
end



local function activate_logging()
	-- Create the log file and redirect the print function.
	if strLogFileName~=nil then
		tLogFile,strError = io.open(strLogFileName, "w")
		if tLogFile==nil then
			error(string.format("Failed to open the logfile %s for writing: %s", strLogFileName, strError))
		end
	end
	_G.print_original = _G.print
	_G.print = logfile_print
	_G.print_raw = logfile_print_raw
end



local function deactivate_logging()
	-- Restore the original print vector.
	_G.print = _G.print_original
	
	-- Close the logfile.
	if strLogFileName~=nil then
		tLogFile:close()
	end
end



local function open_netx_connection()
	-- Open the connection to the netX.
	if string.upper(strInterfacePattern)~="ASK" then
		-- No interface detected yet.
		local tPlugin = nil
		
		-- Detect all interfaces.
		local aDetectedInterfaces = {}
		for iCnt,tPlugin in ipairs(__MUHKUH_PLUGINS) do
			tPlugin:DetectInterfaces(aDetectedInterfaces)
		end
		
		-- Search all detected interfaces for the pattern.
		for iInterfaceIdx,tInterface in ipairs(aDetectedInterfaces) do
			local strName = tInterface:GetName()
			if string.match(strName, strInterfacePattern)~=nil then
				tPlugin = aDetectedInterfaces[iInterfaceIdx]:Create()
				
				-- Connect the plugin.
				tPlugin:Connect()
				
				break
			end
		end
		
		-- Found the interface?
		if tPlugin==nil then
			error(string.format("No interface matched the pattern '%s'!", strInterfacePattern))
		end
		
		tester.setCommonPlugin(tPlugin)
	end
end


local function run_tests()
	-- Run all enabled modules with their parameter.
	local fTestResult = true
	
	for iCnt,uiTestCase in ipairs(auiTests) do
		tModule = aModules[uiTestCase]
		if tModule==nil then
			error(string.format("Test case %02d not found!", uiTestCase))
		end
		
		-- Show all parameters for the test case.
		print("__/Parameters/________________________________________________________________")
		print(string.format("Parameters for testcase %d (%s):", uiTestCase, tModule.CFG_strTestName))
		show_parameters(uiTestCase)
		print("______________________________________________________________________________")
		
		-- Get the parameters for the module.
		local atParameters = atAllParameters[uiTestCase]
		
		-- Execute the test code.
		fStatus, tResult = pcall(tModule.run, atParameters)
		if not fStatus then
			print("Error running the test:")
			print(tResult)
			
			fTestResult = false
			break;
		end
	end
	
	-- Close the connection to the netX.
	tester.closeCommonPlugin()
	
	return fTestResult
end



function run(astrArg, auiTestCases)
	local fResult = nil
	
	collect_testcases(auiTestCases)
	parse_commandline_arguments(arg, auiTestCases)
	
	if fShowParameters==true then
		show_all_parameters()
	else
		collect_parameters()
		check_parameters()
		
		activate_logging()
		open_netx_connection()
		fResult = run_tests()
		deactivate_logging()
	end
	
	return fResult
end


