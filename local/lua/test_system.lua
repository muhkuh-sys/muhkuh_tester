module("test_system", package.seeall)

------------------------------------------------------------------------------


local strTesterVersion = '${PROJECT_VERSION}'
local strTesterVcsVersion = '${PROJECT_VERSION_VCS}'

-- The "show parameter" mode is disabled by default.
local fShowParameters = false

-- No log file.
local tLogFile = nil

-- Run over all available test cases and get the test modules.
local atModules = {}

-- This list collects all parameters from the CLI. They are not split into their components.
local astrRawParameters = {}

-- This list collects all test cases to run.
local auiTests = nil

-- This is the list of the system parameters.
local m_atSystemParameter = nil

-- This is the filename of the log file.
local strLogFileName = nil

local pl = require'pl.import_into'()
local argparse = require 'argparse'
local TestDescription = require 'test_description'

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


------------------------------------------------------------------------------


local function collect_testcases()
  local tResult = true

  for _, uiTestCase in ipairs(auiTests) do
    -- Does a test with this number already exist?
    if atModules[uiTestCase]~=nil then
      tLogSystem.fatal('More than one test with the index %d exists.', uiTestCase)
      tResult = nil
      break
    end

    -- Create the filename for the test case.
    local strTestCaseFilename = string.format("test%02d", uiTestCase)

    -- Load the test case.
    local tClass = require(strTestCaseFilename)
    local tModule = tClass(uiTestCase, tLogWriter, strLogLevel)
    atModules[uiTestCase] = tModule
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
  for uiTestCase,tModule in ipairs(atModules) do
    local strTestName = tModule.CFG_strTestName
    print(string.format("  Test case %02d: '%s'", uiTestCase, strTestName))

    local atPrint = {}
    for iCnt1,tParameter in ipairs(tModule.CFG_aParameterDefinitions) do
      if tParameter.fHasDefaultValue~=true then
        strDefault = "no default value"
      else
        strDefault = string.format("default: %s", tostring(tParameter.tDefaultValue))
      end
      table.insert(atPrint, { string.format("%02d:%s", uiTestCase, tParameter.strName), {tParameter.strHelp, strDefault}})
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
  for iCnt,tModule in ipairs(atModules) do
    if tModule.CFG_strTestName==strModuleName then
      iResult = iCnt
      break
    end
  end

  return iResult
end



local function parse_commandline_arguments()
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
  tParser:mutex(
    tParser:flag('--color')
      :description('Use colors to beautify the console output. This is the default on Linux.')
      :action("store_true")
      :target('fUseColor'),
    tParser:flag('--no-color')
      :description('Do not use colors for the console output. This is the default on Windows.')
      :action("store_false")
      :target('fUseColor')
  )
  tParser:option('-l --logfile')
    :description('Write all output to FILE.')
    :argname('<FILE>')
    :default(nil)
    :target('strLogFileName')
  tParser:flag('-i --interactive-plugin-selection')
    :description('Ask the user to pick a plugin. The default is to select a plugin automatically.')
    :default(false)
    :target('fInteractivePluginSelection')
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

  -- Save the selected log level.
  strLogLevel = tArgs.strLogLevel

  fShowParameters = tArgs.fShowParameters

  local fUseColor = tArgs.fUseColor
  if fUseColor==nil then
    if strDirectorySeparator=='\\' then
      -- Running on windows. Do not use colors here as the default cmd.exe does
      -- not support this.
      fUseColor = false
    else
      -- Running on Linux. Use colors.
      fUseColor = true
    end
  end

  -- Collect all log writers.
  local atLogWriters = {}

  -- Create the console logger.
  local tLogWriterConsole
  if fUseColor==true then
    tLogWriterConsole = require 'log.writer.console.color'.new()
  else
    tLogWriterConsole = require 'log.writer.console'.new()
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

  -- If no test cases were specified run all of them.
  if #tArgs.auiTests~=0 then
    auiTests = tArgs.auiTests
  end
end



local function process_one_parameter(strParameterLine, atCliParameters)
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
          tResult = process_one_parameter(strLine, atCliParameters)
          if tResult~=true then
            break
          end
        end
      end
    end
  else
    tLogSystem.debug('Processing parameter "%s".', strParameterLine)
    local uiTestCase
    -- Try to parse the parameter line with a test number ("01:key=value").
    strTestCase, strParameterName, strValue = string.match(strParameterLine, "([0-9]+):([0-9a-zA-Z_]+)=(.*)")
    if strTestCase==nil then
      -- Try to parse the parameter line with a test name ("EthernetTest:key=value").
      strTestCase, strParameterName, strValue = string.match(strParameterLine, "([0-9a-zA-Z_]+):([0-9a-zA-Z_]+)=(.*)")
      if strTestCase==nil then
        tLogSystem.fatal("The parameter definition has an invalid format: '%s'", strParameterLine)
        tResult = nil
      else
        if strTestCase=='system' then
          uiTestCase = 0
        else
          -- Get the number for the test case name.
          uiTestCase = get_module_index(strTestCase)
          if uiTestCase==nil then
            tLogSystem.fatal('The parameter "%s" uses an unknown test name: "%s".', strParameterLine, strTestCase)
            tResult = nil
          end
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
      table.insert(atCliParameters, {id=uiTestCase, name=strParameterName, value=strValue})
    end
  end

  return tResult
end



local function collect_parameters(tTestDescription)
  local tResult = true

  -- Collect all parameters from the command line.
  local atCliParameters = {}
  for _, strParameter in ipairs(astrRawParameters) do
    tResult = process_one_parameter(strParameter, atCliParameters)
    if tResult~=true then
      break
    end
  end

  -- Apply all system parameters.
  for _, tParam in pairs(atCliParameters) do
    -- Is this a system parameter?
    if tParam.id==0 then
      -- Set the parameter.
      tLogSystem.debug('Setting system parameter "%s" to %s.', tParam.name, tParam.value)
      m_atSystemParameter[tParam.name] = tParam.value
    end
  end

  if tResult==true then
    -- Get all test names.
    local astrTestNames = tTestDescription:getTestNames()

    -- Loop over all active tests and apply the tests from the XML.
    local uiNumberOfTests = tTestDescription:getNumberOfTests()
    for uiTestIndex = 1, uiNumberOfTests do
      local tModule = atModules[uiTestIndex]
      local strTestCaseName = astrTestNames[uiTestIndex]

      if tModule==nil then
        tLogSystem.debug('Skipping deactivated test %02d:%s .', uiTestIndex, strTestCaseName)
      else
        -- Get the parameters for the module.
        local atParametersModule = tModule.atParameter or {}

        -- Get the parameters from the XML.
        local atParametersXml = tTestDescription:getTestCaseParameters(uiTestIndex)
        for _, tParameter in ipairs(atParametersXml) do
          local strParameterName = tParameter.name
          local strParameterValue = tParameter.value
          local strParameterConnection = tParameter.connection

          -- Does the parameter exist?
          tParameter = atParametersModule[strParameterName]
          if tParameter==nil then
            tLogSystem.fatal('The parameter "%s" does not exist in test case %d (%s).', strParameterName, uiTestIndex, strTestCaseName)
            tResult = nil
            break
          else
            if strParameterValue~=nil then
              -- This is a direct assignment of a value.
              tParameter:set(strParameterValue)
            elseif strParameterConnection~=nil then
              -- This is a connection to another value.
              local strClass, strName = string.match(strParameterConnection, '^([^:]+):(.+)')
              if strClass==nil then
                tLogSystem.fatal('Parameter "%s" of test %d has an invalid connection "%s".', strParameterName, uiTestIndex, strParameterConnection)
                tResult = nil
                break
              else
                -- For now accept only system values.
                if strClass~='system' then
                  tLogSystem.fatal('The connection target "%s" has an unknown class.', strParameterConnection)
                  tResult = nil
                  break
                else
                  tValue = m_atSystemParameter[strName]
                  if tValue==nil then
                    tLogSystem.fatal('The connection target "%s" has an unknown name.', strParameterConnection)
                    tResult = nil
                    break
                  else
                    tParameter:set(tostring(tValue))
                  end
                end
              end
            end
          end
        end
      end
    end

    -- Apply all parameters from the command line.
    for _, tParam in pairs(atCliParameters) do
      local uiModuleId = tParam.id
      local strParameterName = tParam.name
      tLogSystem.debug('Apply CLI parameter for module #%d, "%s"="%s".', uiModuleId, strParameterName, tParam.value)

      -- Get the module.
      local tModule
      -- Do not process system parameters here.
      if uiModuleId~=0 then
        tModule = atModules[uiModuleId]
        if tModule==nil then
          tLogSystem.fatal('No module with index %d found.', uiModuleId)
          tResult = nil
          break
        else
          -- Get the parameter.
          local tParameter = tModule.atParameter[strParameterName]
          if tParameter==nil then
            tLogSystem.fatal('Module %d has no parameter "%s".', uiModuleId, strParameterName)
            tResult = nil
            break
          else
            -- Set the parameter.
            tParameter:set(tParam.value)
          end
        end
      end
    end
  end

  return tResult
end



local function check_parameters(tTestDescription)
  -- Check all parameters.
  local fParametersOk = true

  -- Get all test names.
  local astrTestNames = tTestDescription:getTestNames()

  -- Loop over all active tests.
  local uiNumberOfTests = tTestDescription:getNumberOfTests()
  for uiTestIndex = 1, uiNumberOfTests do
    local tModule = atModules[uiTestIndex]
    local strTestCaseName = astrTestNames[uiTestIndex]

    if tModule==nil then
      tLogSystem.debug('Skipping deactivated test %02d:%s .', uiTestIndex, strTestCaseName)
    else
      -- Get the parameters for the module.
      local atParameters = tModule.CFG_aParameterDefinitions

      for _, tParameter in ipairs(tModule.CFG_aParameterDefinitions) do
        -- Validate the parameter.
        local fValid, strError = tParameter:validate()
        if fValid==false then
          tLogSystem.fatal('The parameter %02d:%s is invalid: %s', uiTestIndex, tParameter.strName, strError)
          fParametersOk = false
        end
      end
    end
  end

  if fParametersOk==false then
    tLogSystem.fatal('One or more parameters were invalid. Not running the tests!')
  end

  return fParametersOk
end



local function run_tests()
  -- Run all enabled modules with their parameter.
  local fTestResult = true

  for iCnt,uiTestCase in ipairs(auiTests) do
    -- Get the module for the test index.
    tModule = atModules[uiTestCase]
    if tModule==nil then
      tLogSystem.fatal('Test case %02d not found!', uiTestCase)
      fTestResult = false
      break
    end

    -- Get the name for the test case index.
    local strTestCaseName = tModule.CFG_strTestName
    tLogSystem.info('Running testcase %d (%s).', uiTestCase, strTestCaseName)

    -- Get the parameters for the module.
    local atParameters = tModule.CFG_aParameterDefinitions

    -- Show all parameters for the test case.
    tLogSystem.info("__/Parameters/________________________________________________________________")
    if pl.tablex.size(atParameters)==0 then
      tLogSystem.info('Testcase %d (%s) has no parameter.', uiTestCase, strTestCaseName)
    else
      tLogSystem.info('Parameters for testcase %d (%s):', uiTestCase, strTestCaseName)
      for _, tParameter in pairs(atParameters) do
        tLogSystem.info('  %02d:%s = %s', uiTestCase, tParameter.strName, tParameter:get_pretty())
      end
    end
    tLogSystem.info("______________________________________________________________________________")

    -- Execute the test code. Write a stack trace to the debug logger if the test case crashes.
    fStatus, tResult = xpcall(function() tModule:run() end, function(tErr) tLogSystem.debug(debug.traceback()) return tErr end)
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
  tester:closeCommonPlugin()

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



function run()
  parse_commandline_arguments()

  -- Store the system parameters here.
  m_atSystemParameter = {}

  -- Read the test.xml file.
  local tTestDescription = TestDescription(tLogSystem)
  local tResult = tTestDescription:parse('tests.xml')
  if tResult~=true then
    tLogSystem.error('Failed to parse the test description.')
  else
    -- Run all tests if no test numbers were specified on the command line.
    local uiTestCases = tTestDescription:getNumberOfTests()
    if auiTests==nil then
      -- Run all tests.
      auiTests = {}
      for uiCnt=1, uiTestCases do
        table.insert(auiTests, uiCnt)
      end
    else
      -- Check if the selection does not exceed the number of tests.
      local fOk = true
      for _, uiTestIndex in ipairs(auiTests) do
        if uiTestIndex>uiTestCases then
          tLogSystem.error('The selected test %d exceeds the number of total tests.', uiTestIndex)
          fOk = false
        end
      end
      if fOk~=true then
        error('Invalid test index.')
      end
    end

    -- Create the global tester.
    local cTester = require 'tester_cli'
    _G.tester = cTester(tLogSystem)

    tResult = collect_testcases()
    if tResult==true then
      if fShowParameters==true then
        show_all_parameters()
      else
        tResult = collect_parameters(tTestDescription)
        if tResult==true then
          tResult = check_parameters(tTestDescription)
          if tResult==true then
            tResult = run_tests()
          end
        end
      end
    end
  end

  return fResult
end


