module("test_system", package.seeall)

------------------------------------------------------------------------------


local strTesterVersion = '${PROJECT_VERSION}'
local strTesterVcsVersion = '${PROJECT_VERSION_VCS}'

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

local pl = require'pl.import_into'()
local argparse = require 'argparse'

-- This is a log writer connected to all outputs (console and optionally file).
-- It is used to create new log targets with special prefixes for each test.
local tLogWriter = nil
-- This is the selected log level.
local strLogLevel = nil

-- This is a logger with "SYSTEM" prefix.
local tLogSystem = nil

-- Prepend the default parameter file before all other parameters if no '-P'
-- option was specified.
local strDefaultParameterFile = 'parameters.txt'

local fHaveNetx = nil


------------------------------------------------------------------------------


local function collect_testcases(auiTestCases)
  local tResult = true

  for iCnt,uiTestCase in ipairs(auiTestCases) do
    -- Does a test with this number already exist?
    if aModules[uiTestCase]~=nil then
      tLogSystem.fatal('More than one test with the index %d exists.', uiTestCase)
      tResult = nil
      break
    end

    -- Create the filename for the test case.
    local strTestCaseFilename = string.format("test%02d", uiTestCase)

    -- Load the test case.
    local tModule = require(strTestCaseFilename)
    aModules[uiTestCase] = tModule
  end

  return tResult
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



--- Get the index of a module.
-- Search a module by its name and return the index.
-- @param strModuleName The module name to search.
-- @return The index if the name was found or nil if the name was not found.
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


--- Find a parameter in a module.
-- Search the parameter list of a module for one name.
-- The search is done with an exact compare, so there are no wildcards or
-- regular expressions.
-- @param tModule The module to do the search in.
-- @param strParameterName The exact name of the parameter.
-- @return The parameter structure if the name was found, or nil if the name was not found.
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



local function parse_commandline_arguments(astrArg, auiAllTestCases)
  local atLogLevels = {
    'debug',
    'info',
    'warning',
    'error',
    'fatal'
  }

  local tParser = argparse('tester', 'A test framework.')
  -- "--version" is special. It behaves like a command and is processed immediately during parsing.
  tParser:flag('--version')
    :description('Show the version and exit.')
    :action(function()
      print(string.format('tester V%s %s', strTesterVersion, strTesterVcsVersion))
      os.exit(0)
    end)
  tParser:argument('testcase', 'Run only testcase INDEX.')
    :argname('<INDEX>')
    :convert(function (strArg)
      local ulArg = tonumber(strArg)
      if ulArg==nil then
        return nil, string.format('The test index "%s" is not a number.', strArg)
      else
        return ulArg
      end
    end)
    :args('*')
    :target('auiTests')
  tParser:flag('-s --show-parameters')
    :description('Show all available parameters for all test cases. Do not run any tests.')
    :default(false)
    :target('fShowParameters')
  tParser:option('-l --logfile')
    :description('Write all output to FILE.')
    :argname('<FILE>')
    :default(nil)
    :target('strLogFileName')
  tParser:option('-i --interface')
    :description('Select the first interface which matches the INTERFACE-PATTERN. The special value ASK shows a menu with all available interfaces and prompts the user to select one.')
    :argname('<INTERFACE-PATTERN>')
    :default('ASK')
    :target('strInterfacePattern')
  tParser:option('-p --parameter')
    :description('Set the parameter PARAMETER of test case TEST-CASE-ID to the value VALUE.')
    :argname('<TEST-CASE-ID>:<PARAMETER>=<VALUE>')
    :count('*')
    :convert(function(strArg)
      local tMatch = string.match(strArg, "([0-9a-zA-Z_]+):([0-9a-zA-Z_]+)=(.*)")
      if tMatch==nil then
        return nil, string.format("The parameter definition has an invalid format: '%s'", strArg)
      else
        return strArg
      end
    end)
    :target('astrRawParameters')
  tParser:option('-P --parameter-file')
    :description('Read parameters from FILE.')
    :argname('<FILE>')
    :count('*')
    :convert(function(strArg)
      return '@' .. strArg
    end)
    :target('astrRawParameters')
  tParser:option('-v --verbose')
    :description(string.format('Set the verbosity level to LEVEL. Possible values for LEVEL are %s.', table.concat(atLogLevels, ', ')))
    :argname('<LEVEL>')
    :default('warning')
    :convert(function(strArg)
      local tIdx = pl.tablex.find(atLogLevels, strArg)
      if tIdx==nil then
        return nil, string.format('Invalid verbosity level "%s". Possible values are %s.', strArg, table.concat(atLogLevels, ', '))
      else
        return strArg
      end
    end)
    :target('strLogLevel')


  local tArgs = tParser:parse()
  pl.pretty.dump(tArgs)

  -- Save the selected log level.
  strLogLevel = tArgs.strLogLevel

  -- Save the slected interface.
  strInterfacePattern = tArgs.strInterfacePattern

  fShowParameters = tArgs.fShowParameters

  -- Collect all log writers.
  local atLogWriters = {}

  -- Create the console logger.
  local tLogWriterConsole
  local strDirectorySeparator = package.config:sub(1,1)
  if strDirectorySeparator=='\\' then
    -- Running on windows. Do not use colors here as the default cmd.exe does
    -- not support this.
    tLogWriterConsole = require 'log.writer.console'.new()
  else
    -- Running on Linux. Use colors.
    tLogWriterConsole = require 'log.writer.console.color'.new()
  end
  table.insert(atLogWriters, tLogWriterConsole)

  -- Create the file logger if requested.
  local tLogWriterFile
  if tArgs.strLogFileName~=nil then
    tLogWriterFile = require 'log.writer.file'.new{ log_name=tArgs.strLogFileName }
    table.insert(atLogWriters, tLogWriterFile)
  end

  -- Combine all writers.
  tLogWriter = require 'log.writer.list'.new(unpack(atLogWriters))

  -- Create a new log target with "SYSTEM" prefix.
  local tLogWriterSystem = require 'log.writer.prefix'.new('[System] ', tLogWriter)
  tLogSystem = require "log".new(
    -- maximum log level
    strLogLevel,
    tLogWriterSystem,
    -- Formatter
    require "log.formatter.format".new()
  )


  astrRawParameters = tArgs.astrRawParameters
  -- Search the list of parameters for a file (i.e. a string entry).
  local fParameterFileOnCli = false
  for _, tParameter in pairs(astrRawParameters) do
    if type(tParameter)=='string' then
      -- This is a parameter file.
      fParameterFileOnCli = true
      break
    end
  end
  -- If no parameter file was specified, check if the default parameter file exists.
  if fParameterFileOnCli~=true then
    tLogSystem.debug('No parameter file specified. Checking for the default file "%s".', strDefaultParameterFile)
    local strParametersFile = pl.path.exists(strDefaultParameterFile)
    if strParametersFile==nil then
      tLogSystem.debug('The default parameter file does not exist.')
    else
      tLogSystem.debug('The default parameter file exists, inserting it before all other parameter.')
      table.insert(astrRawParameters, 1, '@' .. strParametersFile)
    end
  end

  -- If no test cases were specified run all of them.
  if #tArgs.auiTests==0 then
    auiTests = auiAllTestCases
  else
    auiTests = tArgs.auiTests
  end
end



local function process_one_parameter(atParameters, strParameterLine)
  local tResult = true

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
    tLogSystem.debug('Processing parameter file "%s".', strFilename)
    if pl.path.exists(strFilename)==nil then
      tLogSystem.fatal('The parameter file "%s" does not exist.', strFilename)
      tResult = nil
    else
      -- Iterate over all lines.
      for strLine in io.lines(strFilename) do
        if strLine~=nil then
          tResult = process_one_parameter(atParameters, strLine)
          if tResult~=true then
            break
          end
        end
      end
    end
  else
    tLogSystem.debug('Processing parameter "%s".', strParameterLine)
    -- Try to parse the parameter line with a test number ("01:key=value").
    strTestCase, strParameterName, strValue = string.match(strParameterLine, "([0-9]+):([0-9a-zA-Z_]+)=(.*)")
    if strTestCase==nil or strParameterName==nil or strValue==nil then
      -- Try to parse the parameter line with a test name ("EthernetTest:key=value").
      strTestCase, strParameterName, strValue = string.match(strParameterLine, "([0-9a-zA-Z_]+):([0-9a-zA-Z_]+)=(.*)")
      if strTestCase==nil or strParameterName==nil or strValue==nil then
        tLogSystem.fatal("The parameter definition has an invalid format: '%s'", strParameterLine)
        tResult = nil
      else
        -- Get the number for the test case name.
        uiTestCase = get_module_index(strTestCase)
        if uiTestCase==nil then
          tLogSystem.fatal('The parameter "%s" uses an unknown test name: "%s".', strParameterLine, strTestCase)
          tResult = nil
        end
      end
    else
      uiTestCase = tonumber(strTestCase)
      if uiTestCase==nil then
        tLogSystem.fatal('The parameter "%s" uses an invalid number for the test index: "%s".', strParameterLine, strTestCase)
        tResult = nil
      end
    end

    if tResult~=nil then
      tModule = aModules[uiTestCase]
      if tModule==nil then
        tLogSystem.fatal('The parameter "%s" uses an unknown module with index "%d".', strParameterLine, uiTestCase)
        tResult = nil
      else
        tParameter = find_parameter(tModule, strParameterName)
        if tParameter==nil then
          tLogSystem.fatal('The parameter "%s" uses the non-existing key "%s".', strParameterLine, strParameterName)
          tResult = nil
        else
          -- Add the parameter to the array.
          if atAllParameters[uiTestCase]==nil then
            atParameters[uiTestCase] = {}
          end
          local atModuleParameter = atParameters[uiTestCase]
          atModuleParameter[strParameterName] = strValue
        end
      end
    end
  end

  return tResult
end



local function collect_parameters()
  local tResult = true

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
    tResult = process_one_parameter(atAllParameters, strParameter)
    if tResult~=true then
      break
    end
  end

  return tResult
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
          tLogSystem.fatal('The mandatory parameter %02d:%s is missing.', uiTestCase, tParameter.name)
          fParametersOk = false
        end
      else
        -- The parameter exists. Check the value if a validate function exists.
        if tParameter.validate~=nil then
          fValid, strError = tParameter.validate(tValue, tParameter.constrains)
          if fValid==false then
            tLogSystem.fatal('The parameter %02d:%s is invalid: %s', uiTestCase, tParameter.name, strError)
            fParametersOk = false
          end
        end
      end
    end
  end

  if fParametersOk==false then
    tLogSystem.fatal('One or more parameters were invalid. Not running the tests!')
  end

  return fParametersOk
end



local function open_netx_connection()
  local tResult = true

  -- Open the connection to the netX.
  if fHaveNetx==true then
    if string.upper(strInterfacePattern)=="ASK" then
      tLogSystem.debug('Not opening a default netX connection as the interface pattern is "ASK".')
    else
      -- No interface detected yet.
      local tPlugin = nil

      -- Detect all interfaces.
      local aDetectedInterfaces = {}
      for iCnt,tPlugin in ipairs(__MUHKUH_PLUGINS) do
        tPlugin:DetectInterfaces(aDetectedInterfaces)
      end

      -- Search all detected interfaces for the pattern.
      tLogSystem.debug('Searching for an interface with the pattern "%s".', strInterfacePattern)
      for iInterfaceIdx, tInterface in ipairs(aDetectedInterfaces) do
        local strName = tInterface:GetName()
        if string.match(strName, strInterfacePattern)==nil then
          tLogSystem.debug('Not connection to plugin "%s" as it does not match the interface pattern.', strName)
        else
          tLogSystem.info('Connecting to plugin "%s".', strName)
          tPlugin = aDetectedInterfaces[iInterfaceIdx]:Create()

          tPlugin:Connect()

          break
        end
      end

      -- Found the interface?
      if tPlugin==nil then
        tLogSystem.fatal('No interface matched the pattern "%s".', strInterfacePattern)
        tResult = nil
      else
        tester.setCommonPlugin(tPlugin)
      end
    end
  end

  return tResult
end



local function close_netx_connection()
  if fHaveNetx==true then
    tLogSystem.debug('Closing any netX connection.')
    tester.closeCommonPlugin()
  end
end



local function run_tests()
  -- Run all enabled modules with their parameter.
  local fTestResult = true

  for iCnt,uiTestCase in ipairs(auiTests) do
    -- Get the module for the test index.
    tModule = aModules[uiTestCase]
    if tModule==nil then
      tLogSystem.fatal('Test case %02d not found!', uiTestCase)
      fTestResult = false
      break
    end

    -- Get the name for the test case index.
    local strTestCaseName = tModule.CFG_strTestName
    tLogSystem.info('Running testcase %d (%s).', uiTestCase, strTestCaseName)

    -- Get the parameters for the module.
    local atParameters = atAllParameters[uiTestCase]

    -- Show all parameters for the test case.
    tLogSystem.info("__/Parameters/________________________________________________________________")
    if pl.tablex.size(atParameters)==0 then
      tLogSystem.info('Testcase %d (%s) has no parameter.', uiTestCase, strTestCaseName)
    else
      tLogSystem.info('Parameters for testcase %d (%s):', uiTestCase, strTestCaseName)
      for strParameterName, strParameterValue in pairs(atParameters) do
        tLogSystem.info('  %02d:%s = %s', uiTestCase, strParameterName, strParameterValue)
      end
    end
    tLogSystem.info("______________________________________________________________________________")

    -- Create a new log target for the testcase.
    local tLogWriterTestcase = require 'log.writer.prefix'.new(
      string.format('[Test %02d] ', uiTestCase),
      tLogWriterConsole
    )
    local tLogTestcase = require 'log'.new(
      -- maximum log level
      strLogLevel,
      tLogWriterTestcase,
      -- Formatter
      require 'log.formatter.format'.new()
    )

    -- Execute the test code.
    fStatus, tResult = pcall(tModule.run, tModule, atParameters, tLogTestcase)
    tLogSystem.info('Testcase %d (%s) finished.', uiTestCase, strTestCaseName)
    if not fStatus then
      local strError
      if tResult~=nil then
        strError = tostring(tResult)
      else
        strError = 'No error message.'
      end
      tLogSystem.error('Error running the test: %s', strError)

      fTestResult = false
      break
    end
  end

  -- Close the connection to the netX.
  close_netx_connection()

  -- Print the result in huge letters.
  if fTestResult==true then
    tLogSystem.info('***************************************')
    tLogSystem.info('*                                     *')
    tLogSystem.info('* ######## ########  ######  ######## *')
    tLogSystem.info('*    ##    ##       ##    ##    ##    *')
    tLogSystem.info('*    ##    ##       ##          ##    *')
    tLogSystem.info('*    ##    ######    ######     ##    *')
    tLogSystem.info('*    ##    ##             ##    ##    *')
    tLogSystem.info('*    ##    ##       ##    ##    ##    *')
    tLogSystem.info('*    ##    ########  ######     ##    *')
    tLogSystem.info('*                                     *')
    tLogSystem.info('*          #######  ##    ##          *')
    tLogSystem.info('*         ##     ## ##   ##           *')
    tLogSystem.info('*         ##     ## ##  ##            *')
    tLogSystem.info('*         ##     ## #####             *')
    tLogSystem.info('*         ##     ## ##  ##            *')
    tLogSystem.info('*         ##     ## ##   ##           *')
    tLogSystem.info('*          #######  ##    ##          *')
    tLogSystem.info('*                                     *')
    tLogSystem.info('***************************************')
  else
    tLogSystem.error('*******************************************************')
    tLogSystem.error('*                                                     *')
    tLogSystem.error('*         ######## ########  ######  ########         *')
    tLogSystem.error('*            ##    ##       ##    ##    ##            *')
    tLogSystem.error('*            ##    ##       ##          ##            *')
    tLogSystem.error('*            ##    ######    ######     ##            *')
    tLogSystem.error('*            ##    ##             ##    ##            *')
    tLogSystem.error('*            ##    ##       ##    ##    ##            *')
    tLogSystem.error('*            ##    ########  ######     ##            *')
    tLogSystem.error('*                                                     *')
    tLogSystem.error('* ########    ###    #### ##       ######## ########  *')
    tLogSystem.error('* ##         ## ##    ##  ##       ##       ##     ## *')
    tLogSystem.error('* ##        ##   ##   ##  ##       ##       ##     ## *')
    tLogSystem.error('* ######   ##     ##  ##  ##       ######   ##     ## *')
    tLogSystem.error('* ##       #########  ##  ##       ##       ##     ## *')
    tLogSystem.error('* ##       ##     ##  ##  ##       ##       ##     ## *')
    tLogSystem.error('* ##       ##     ## #### ######## ######## ########  *')
    tLogSystem.error('*                                                     *')
    tLogSystem.error('*******************************************************')
  end

  return fTestResult
end



function run(astrArg, auiTestCases)
  parse_commandline_arguments(astrArg, auiTestCases)

  -- Does the "tester" module exist?
  if package.loaded['tester']~=nil then
    tLogSystem.debug('Module "tester" found. Assuming a netX connection.')
    fHaveNetx = true
  else
    tLogSystem.debug('Module "tester" not found. Assuming no netX connection.')
    fHaveNetx = false
  end

  tResult = collect_testcases(auiTestCases)
  if tResult==true then
    if fShowParameters==true then
      show_all_parameters()
    else
      tResult = collect_parameters()
      if tResult==true then
        tResult = check_parameters()
        if tResult==true then
          tResult = open_netx_connection()
          if tResult==true then
            tResult = run_tests()
          end
        end
      end
    end
  end

  return fResult
end


