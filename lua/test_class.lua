local class = require 'pl.class'
local TestClass = class()

function TestClass:_init(strTestName, uiTestCase, tLogWriter, strLogLevel)
  self.P = require 'parameter_instances'(strTestName, tLogWriter, strLogLevel)
  self.pl = require'pl.import_into'()

  -- Create a new log target for this test.
  local tLogWriterTestcase = require 'log.writer.prefix'.new(
    string.format('[Test %02d] ', uiTestCase),
    tLogWriter
  )
  self.tLog = require 'log'.new(
    -- maximum log level
    strLogLevel,
    tLogWriterTestcase,
    -- Formatter
    require 'log.formatter.format'.new()
  )

  self.CFG_strTestName = strTestName
  self.CFG_uiTestCase = uiTestCase
  self.CFG_aParameterDefinitions = {}
end



function TestClass:__parameter(atParameter)
  self.CFG_aParameterDefinitions = atParameter

  -- Build a lookup table with the parameter name as the key.
  local atParameterLookUp = {}
  for _, tParameter in pairs(atParameter) do
    local strName = tParameter.strName
    if atParameterLookUp[strName]~=nil then
      self.tLog.error('The test defines the parameter "%s" more than once.', strName)
      error('Invalid parameter definition.')
    end
    atParameterLookUp[strName] = tParameter
  end
  self.atParameter = atParameterLookUp
end



return TestClass
