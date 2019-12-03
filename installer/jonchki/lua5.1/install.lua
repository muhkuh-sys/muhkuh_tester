local t = ...
local strDistId, strDistVersion, strCpuArch = t:get_platform()
local tResult = true


local tPostTriggerAction = {}

--- Expat callback function for starting an element.
-- This function is part of the callbacks for the expat parser.
-- It is called when a new element is opened.
-- @param tParser The parser object.
-- @param strName The name of the new element.
function tPostTriggerAction.__parseTests_StartElement(tParser, strName, atAttributes)
  local aLxpAttr = tParser:getcallbacks().userdata
  local iPosLine, iPosColumn, iPosAbs = tParser:pos()

  table.insert(aLxpAttr.atCurrentPath, strName)
  local strCurrentPath = table.concat(aLxpAttr.atCurrentPath, "/")
  aLxpAttr.strCurrentPath = strCurrentPath

  if strCurrentPath=='/MuhkuhTest/Testcase' then
    local strID = atAttributes['id']
    local strFile = atAttributes['file']
    local strName = atAttributes['name']
    if (strID==nil or strID=='') and (strFile==nil or strFile=='') then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: one of "id" or "file" must be present, but none found.', iPosLine, iPosColumn)
    elseif (strID~=nil and strID~='') and (strFile~=nil and strFile~='') then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: one of "id" or "file" must be present, but both found.', iPosLine, iPosColumn)
    elseif strName==nil or strName=='' then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: missing "name".', iPosLine, iPosColumn)
    else
      local tTestCase = {
        id = strID,
        file = strFile,
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
      aLxpAttr.tLog.error('Error in line %d, col %d: missing "name".', iPosLine, iPosColumn)
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
function tPostTriggerAction.__parseTests_EndElement(tParser, strName)
  local aLxpAttr = tParser:getcallbacks().userdata
  local iPosLine, iPosColumn, iPosAbs = tParser:pos()

  local strCurrentPath = aLxpAttr.strCurrentPath

  if strCurrentPath=='/MuhkuhTest/Testcase' then
    table.insert(aLxpAttr.atTestCases, aLxpAttr.tTestCase)
    aLxpAttr.tTestCase = nil
  elseif strCurrentPath=='/MuhkuhTest/Testcase/Parameter' then
    if aLxpAttr.strParameterName==nil then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: missing "name".', iPosLine, iPosColumn)
    elseif aLxpAttr.strParameterData==nil then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: missing data for parameter.', iPosLine, iPosColumn)
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
function tPostTriggerAction.__parseTests_CharacterData(tParser, strData)
  local aLxpAttr = tParser:getcallbacks().userdata

  if aLxpAttr.strCurrentPath=="/MuhkuhTest/Testcase/Parameter" then
    aLxpAttr.strParameterData = strData
  end
end



function tPostTriggerAction:__parse_tests(tLog, strTestsFile)
  local tResult = nil

  -- Read the complete file.
  local strFileData, strError = self.pl.utils.readfile(strTestsFile)
  if strFileData==nil then
    tLog.error('Failed to read the test configuration file "%s": %s', strTestsFile, strError)
  else
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
      tLog = tLog
    }

    local aLxpCallbacks = {}
    aLxpCallbacks._nonstrict    = false
    aLxpCallbacks.StartElement  = self.__parseTests_StartElement
    aLxpCallbacks.EndElement    = self.__parseTests_EndElement
    aLxpCallbacks.CharacterData = self.__parseTests_CharacterData
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
      tLog.error('Failed to parse the test configuration "%s": %s in line %d, column %d, position %d.', strTestsFile, strMsg, uiLine, uiCol, uiPos)
    elseif aLxpAttr.tResult~=true then
      tLog.error('Failed to parse the test configuration.')
    else
      tResult = aLxpAttr.atTestCases
    end
  end

  return tResult
end



function tPostTriggerAction:run(tInstallHelper)
  local tResult = true
  local pl = tInstallHelper.pl
  self.pl = pl
  local tLog = tInstallHelper.tLog
  local lfs = require 'lfs'

  local strTestsFile = 'tests.xml'
  if pl.path.exists(strTestsFile)~=strTestsFile then
    tLog.error('The test configuration file "%s" does not exist.', strTestsFile)
    tResult = nil
  elseif pl.path.isfile(strTestsFile)~=true then
    tLog.error('The path "%s" is no regular file.', strTestsFile)
    tResult = nil
  else
    -- Copy the tests file.
    local strTestsFileContents, strError = pl.utils.readfile(strTestsFile, false)
    if strTestsFileContents==nil then
      tLog.error('Failed to read the file "%s": %s', strTestsFile, strError)
      tResult = nil
    else
      local strDestinationPath = tInstallHelper:replace_template(string.format('${install_base}/%s', strTestsFile))
      tResult, strError = pl.utils.writefile(strDestinationPath, strTestsFileContents, false)
      if tResult~=true then
        tLog.error('Failed to write the file "%s": %s', strDestinationPath, strError)
        tResult = nil
      else
        tLog.debug('Parsing tests file "%s".', strTestsFile)
        local atTestCases = self:__parse_tests(tLog, strTestsFile)
        if atTestCases==nil then
          tLog.error('Failed to parse the test configuration file "%s".', strTestsFile)
          tResult = nil
        else
          -- Run all installer scripts for the test case.
          for uiTestCaseId, tTestCase in ipairs(atTestCases) do
            if tTestCase.id~=nil then
              -- The test ID identifies the artifact providing the test script.
              -- It has the form GROUP.MODULE.ARTIFACT .

              -- Get the path to the test case install script in the depack folder.
              local strDepackPath = tInstallHelper:replace_template(string.format('${depack_path_%s}', tTestCase.id))
              local strInstallScriptPath = pl.path.join(strDepackPath, 'install_testcase.lua')
              tLog.debug('Run test case install script "%s".', strInstallScriptPath)
              if pl.path.exists(strInstallScriptPath)~=strInstallScriptPath then
                tLog.error('The test case install script "%s" for the test %s / %s does not exist.', strInstallScriptPath, tTestCase.id, tTestCase.name)
                tResult = nil
                break
              elseif pl.path.isfile(strInstallScriptPath)~=true then
                tLog.error('The test case install script "%s" for the test %s / %s is no regular file.', strInstallScriptPath, tTestCase.id, tTestCase.name)
                tResult = nil
                break
              else
                -- Call the install script.
                local tFileResult, strError = pl.utils.readfile(strInstallScriptPath, false)
                if tFileResult==nil then
                  tResult = nil
                  tLog.error('Failed to read the test case install script "%s": %s', strInstallScriptPath, strError)
                  break
                else
                  -- Parse the install script.
                  local strInstallScript = tFileResult
                  tResult, strError = loadstring(strInstallScript, strInstallScriptPath)
                  if tResult==nil then
                    tResult = nil
                    tLog.error('Failed to parse the test case install script "%s": %s', strInstallScriptPath, strError)
                    break
                  else
                    local fnInstall = tResult

                    -- Set the artifact's depack path as the current working folder.
                    tInstallHelper:setCwd(strDepackPath)

                    -- Set the current artifact identification for error messages.
                    tInstallHelper:setId('Post Actions')

                    -- Call the install script.
                    tResult, strError = pcall(fnInstall, tInstallHelper, uiTestCaseId, tTestCase.name)
                    if tResult~=true then
                      tResult = nil
                      tLog.error('Failed to run the install script "%s": %s', strInstallScriptPath, tostring(strError))
                      break

                    -- The second value is the return value.
                    elseif strError~=true then
                      tResult = nil
                      tLog.error('The install script "%s" returned "%s".', strInstallScriptPath, tostring(strError))
                      break
                    end
                  end
                end
              end

            elseif tTestCase.file~=nil then
              local strName = tostring(tTestCase.name)

              -- The test case uses a local starter file.
              local strStarterFile = pl.path.exists(tTestCase.file)
              if strStarterFile~=tTestCase.file then
                tLog.error('The start file "%s" for test %s does not exist.', tostring(tTestCase.file), strName)
                tResult = nil
                break
              end

              -- Copy and filter the local file.
              tLog.debug('Installing local test case with ID %02d and name "%s".', uiTestCaseId, strName)

              -- Load the starter script.
              local strTestTemplate, strError = pl.utils.readfile(strStarterFile, false)
              if strTestTemplate==nil then
                tLog.error('Failed to open the test template "%s": %s', strStarterFile, strError)
                tResult = nil
                break
              else
                local astrReplace = {
                  ['ID'] = string.format('%02d', uiTestCaseId),
                  ['NAME'] = strName
                }
                local strTestLua = string.gsub(strTestTemplate, '@([^@]+)@', astrReplace)

                -- Write the test script to the installation base directory.
                local strDestinationPath = tInstallHelper:replace_template(string.format('${install_base}/test%02d.lua', uiTestCaseId))
                local tFileResult, strError = pl.utils.writefile(strDestinationPath, strTestLua, false)
                if tFileResult~=true then
                  tLog.error('Failed to write the test to "%s": %s', strDestinationPath, strError)
                  tResult = nil
                  break
                end
              end

            else
              tLog.error('The test %s has no "id" or "file" attribute.', tostring(tTestCase.name))
              tResult = nil
              break

            end
          end
        end
      end
    end
  end

  return tResult
end


-- Copy the complete "lua" folder.
t:install('lua/', '${install_lua_path}/')

-- Copy the system script.
t:install('system.lua', '${install_base}')

-- Copy the complete "doc" folder.
t:install('doc/', '${install_doc}/')

-- Copy the wrapper.
if strDistId=='windows' then
  t:install('wrapper/windows/tester.bat',  '${install_executables}/')
elseif strDistId=='ubuntu' then
  t:install('wrapper/linux/tester',        '${install_executables}/')
else
  tResult = nil
end

-- Register a new post trigger action.
t:register_post_trigger(tPostTriggerAction.run, tPostTriggerAction, 50)

return tResult
