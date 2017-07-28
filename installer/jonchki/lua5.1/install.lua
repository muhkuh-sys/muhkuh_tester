local t = ...
local tResult = true


--- Expat callback function for starting an element.
-- This function is part of the callbacks for the expat parser.
-- It is called when a new element is opened.
-- @param tParser The parser object.
-- @param strName The name of the new element.
local function parseTests_StartElement(tParser, strName, atAttributes)
  local aLxpAttr = tParser:getcallbacks().userdata
  local iPosLine, iPosColumn, iPosAbs = tParser:pos()

  table.insert(aLxpAttr.atCurrentPath, strName)
  local strCurrentPath = table.concat(aLxpAttr.atCurrentPath, "/")
  aLxpAttr.strCurrentPath = strCurrentPath

  if strCurrentPath=='/MuhkuhTest/Testcase' then
    local strID = atAttributes['id']
    local strName = atAttributes['name']
    if strID==nil or strID=='' then
      aLxpAttr.tResult = nil
      aLxpAttr.tLogger:error('Error in line %d, col %d: missing "id".', iPosLine, iPosColumn)
    elseif strName==nil or strName=='' then
      aLxpAttr.tResult = nil
      aLxpAttr.tLogger:error('Error in line %d, col %d: missing "name".', iPosLine, iPosColumn)
    else
      local tTestCase = {
        id = strID,
        name = strName,
        parameter = {}
      }
      aLxpAttr.tTestCase = tTestCase
      aLxpAttr.strParameterName = nil
      aLxpAttr.strParameterData = nil
    end

  elseif strCurrentPath=='/MuhkuhTest/Testcase/Parameter' then
    local strName = atAttributes['name']
    if strName==nil or strName=='' then
      aLxpAttr.tResult = nil
      aLxpAttr.tLogger:error('Error in line %d, col %d: missing "name".', iPosLine, iPosColumn)
    else
      aLxpAttr.strParameterName = strName
    end
  end
end



--- Expat callback function for closing an element.
-- This function is part of the callbacks for the expat parser.
-- It is called when an element is closed.
-- @param tParser The parser object.
-- @param strName The name of the closed element.
local function parseTests_EndElement(tParser, strName)
  local aLxpAttr = tParser:getcallbacks().userdata
  local iPosLine, iPosColumn, iPosAbs = tParser:pos()

  local strCurrentPath = aLxpAttr.strCurrentPath

  if strCurrentPath=='/MuhkuhTest/Testcase' then
    table.insert(aLxpAttr.atTestCases, aLxpAttr.tTestCase)
    aLxpAttr.tTestCase = nil
  elseif strCurrentPath=='/MuhkuhTest/Testcase/Parameter' then
    if aLxpAttr.strParameterName==nil then
      aLxpAttr.tResult = nil
      aLxpAttr.tLogger:error('Error in line %d, col %d: missing "name".', iPosLine, iPosColumn)
    elseif aLxpAttr.strParameterData==nil then
      aLxpAttr.tResult = nil
      aLxpAttr.tLogger:error('Error in line %d, col %d: missing data for parameter.', iPosLine, iPosColumn)
    else
      table.insert(aLxpAttr.tTestCase.parameter, {name=aLxpAttr.strParameterName, value=aLxpAttr.strParameterData})
    end
  end

  table.remove(aLxpAttr.atCurrentPath)
  aLxpAttr.strCurrentPath = table.concat(aLxpAttr.atCurrentPath, "/")
end



--- Expat callback function for character data.
-- This function is part of the callbacks for the expat parser.
-- It is called when character data is parsed.
-- @param tParser The parser object.
-- @param strData The character data.
local function parseTests_CharacterData(tParser, strData)
  local aLxpAttr = tParser:getcallbacks().userdata

  if aLxpAttr.strCurrentPath=="/MuhkuhTest/Testcase/Parameter" then
    aLxpAttr.strParameterData = strData
  end
end



local function parse_tests(tLogger, strFileData)
  local tResult = nil
  local lxp = require 'lxp'

  local aLxpAttr = {
    -- Start at root ("/").
    atCurrentPath = {""},
    strCurrentPath = nil,

    tTestCase = nil,
    strParameterName = nil,
    strParameterData = nil,
    atTestCases = {},

    tResult = true,
    tLogger = tLogger
  }

  local aLxpCallbacks = {}
  aLxpCallbacks._nonstrict    = false
  aLxpCallbacks.StartElement  = parseTests_StartElement
  aLxpCallbacks.EndElement    = parseTests_EndElement
  aLxpCallbacks.CharacterData = parseTests_CharacterData
  aLxpCallbacks.userdata      = aLxpAttr

  local tParser = lxp.new(aLxpCallbacks)

  local tParseResult, strMsg, uiLine, uiCol, uiPos = tParser:parse(strFileData)
  if tParseResult~=nil then
    tParseResult, strMsg, uiLine, uiCol, uiPos = tParser:parse()
    if tParseResult~=nil then
      tParser:close()
    end
  end

  if tParseResult==nil then
    tLogger:error('Failed to parse the test configuration "%s": %s in line %d, column %d, position %d.', strSourceUrl, strMsg, uiLine, uiCol, uiPos)
  elseif aLxpAttr.tResult~=true then
    tLogger:error('Failed to parse the test configuration.')
  else
    tResult = aLxpAttr.atTestCases
  end

  return tResult
end


-- Copy the complete "lua" folder.
t:install('lua/', '${install_lua_path}/')

-- Copy the complete "doc" folder.
t:install('doc/', '${install_doc}/')

local pl = t.pl
local tLogger = t.cLogger
local lfs = require 'lfs'

local strTestsFile = 'tests.xml'
if pl.path.exists(strTestsFile)==nil then
  tLogger:error('The test configuration file "%s" does not exist.', strTestsFile)
  tResult = nil
elseif pl.path.isfile(strTestsFile)~=true then
  tLogger:error('The path "%s" is no regular file.', strTestsFile)
  tResult = nil
else
  -- Read the complete file.
  local strFileData, strError = t.pl.utils.readfile('tests.xml')
  if strFileData==nil then
    tLogger:error('Failed to read the test configuration file "%s": %s', strTestsFile, strError)
    tResult = nil
  else
    local atTestCases = parse_tests(tLogger, strFileData)
    if atTestCases==nil then
      tLogger:error('Failed to parse the test configuration file "%s".', strTestsFile)
      tResult = nil
    else
      -- Generate the "parameters.txt" file.
      local astrParametersTxt = {}
      for uiTestIndex, tTestCase in ipairs(atTestCases) do
        for _, tParameter in ipairs(tTestCase.parameter) do
          table.insert(astrParametersTxt, string.format('%d:%s=%s', uiTestIndex, tParameter.name, tParameter.value))
        end
      end
      local tFileResult, strError = pl.utils.writefile('parameters.txt', table.concat(astrParametersTxt, '\n'), false)
      if tFileResult~=true then
        tLogger:error('Failed to write the parameters to "parameters.txt": %s', strError)
        tResult = nil
      else
        -- Generate the "system.lua" file.
        local astrSystemLua = {}
        table.insert(astrSystemLua, [[require 'muhkuh_cli_init']])
        table.insert(astrSystemLua, [[require 'test_system']])
        table.insert(astrSystemLua, [[]])
        table.insert(astrSystemLua, [[-- This is a list of all available test cases in this test suite.]])
        table.insert(astrSystemLua, [[-- The test cases are specified by a number starting at 1.]])
        table.insert(astrSystemLua, [[local auiTestCases = {]])
        local uiMaxTestIndex = table.maxn(atTestCases)
        for uiTestIndex, tTestCase in ipairs(atTestCases) do
          strSep = ','
          if uiTestIndex==uiMaxTestIndex then
            strSep = ' '
          end
          table.insert(astrSystemLua, string.format('  %d%s    -- %s', uiTestIndex, strSep, tTestCase.id))
        end
        table.insert(astrSystemLua, [[}]])
        table.insert(astrSystemLua, [[]])
        table.insert(astrSystemLua, [[local fTestResult = test_system.run(arg, auiTestCases)]])
        table.insert(astrSystemLua, [[if fTestResult==true then]])
        table.insert(astrSystemLua, [[  print("OK!")]])
        table.insert(astrSystemLua, [[elseif fTestResult==false then]])
        table.insert(astrSystemLua, [[  error("The test suite failed!")]])
        table.insert(astrSystemLua, [[end]])
        local tFileResult, strError = pl.utils.writefile('system.lua', table.concat(astrSystemLua, '\n'), false)
        if tFileResult~=true then
          tLogger:error('Failed to write the system script to "system.lua": %s', strError)
          tResult = nil
        else
          t:setCwd(lfs.currentdir())
          t:install('parameters.txt', '${install_base}/')
          t:install('system.lua', '${install_base}/')
        end
      end
    end
  end
end

return tResult
