local t = ...


----------------------------------------------------------------------------------------------------------------------
--
-- ActionTestInstaller
--

local function actionTestInstaller(tInstallHelper)
  local tResult
  local pl = tInstallHelper.pl
  local tLog = tInstallHelper.tLog

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
        local tTestDescription = require 'test_description'(tLog)
        local tParseResult = tTestDescription:parse(strTestsFile)
        if tParseResult~=true then
          tLog.error('Failed to parse the test configuration file "%s".', strTestsFile)
          tResult = nil
        else
          -- Run all installer scripts for the test case.
          local uiTestCaseStepMax = tTestDescription:getNumberOfTests()
          for uiTestCaseStepCnt = 1,uiTestCaseStepMax do
            local strTestCaseName = tTestDescription:getTestCaseName(uiTestCaseStepCnt)
            local strTestCaseId = tTestDescription:getTestCaseId(uiTestCaseStepCnt)
            local strTestCaseFile = tTestDescription:getTestCaseFile(uiTestCaseStepCnt)
            if strTestCaseId~=nil then
              -- The test ID identifies the artifact providing the test script.
              -- It has the form GROUP.MODULE.ARTIFACT .

              -- Get the path to the test case install script in the depack folder.
              local strDepackPath = tInstallHelper:replace_template(string.format('${depack_path_%s}', strTestCaseId))
              local strInstallScriptPath = pl.path.join(strDepackPath, 'install_testcase.lua')
              tLog.debug('Run test case install script "%s".', strInstallScriptPath)
              if pl.path.exists(strInstallScriptPath)~=strInstallScriptPath then
                tLog.error(
                  'The test case install script "%s" for the test %s / %s does not exist.',
                  strInstallScriptPath,
                  strTestCaseId,
                  strTestCaseName
                )
                tResult = nil
                break
              elseif pl.path.isfile(strInstallScriptPath)~=true then
                tLog.error(
                  'The test case install script "%s" for the test %s / %s is no regular file.',
                  strInstallScriptPath,
                  strTestCaseId,
                  strTestCaseName
                )
                tResult = nil
                break
              else
                -- Call the install script.
                local tFileResult, strFileError = pl.utils.readfile(strInstallScriptPath, false)
                if tFileResult==nil then
                  tResult = nil
                  tLog.error('Failed to read the test case install script "%s": %s', strInstallScriptPath, strFileError)
                  break
                else
                  -- Parse the install script.
                  local strInstallScript = tFileResult
                  local _loadstring = loadstring or load
                  tResult, strError = _loadstring(strInstallScript, strInstallScriptPath)
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
                    tResult, strError = pcall(fnInstall, tInstallHelper, uiTestCaseStepCnt, strTestCaseName)
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

            elseif strTestCaseFile~=nil then
              -- The test case uses a local starter file.
              local strStarterFile = pl.path.exists(strTestCaseFile)
              if strStarterFile~=strTestCaseFile then
                tLog.error(
                  'The start file "%s" for test %s does not exist.',
                  tostring(strTestCaseFile),
                  strTestCaseName
                )
                tResult = nil
                break
              end

              -- Copy and filter the local file.
              tLog.debug('Installing local test case with ID %02d and name "%s".', uiTestCaseStepCnt, strTestCaseName)

              -- Load the starter script.
              local strTestTemplate, strTemplateError = pl.utils.readfile(strStarterFile, false)
              if strTestTemplate==nil then
                tLog.error('Failed to open the test template "%s": %s', strStarterFile, strTemplateError)
                tResult = nil
                break
              else
                local astrReplace = {
                  ['ID'] = string.format('%02d', uiTestCaseStepCnt),
                  ['NAME'] = strTestCaseName
                }
                local strTestLua = string.gsub(strTestTemplate, '@([^@]+)@', astrReplace)

                -- Write the test script to the installation base directory.
                local strDestinationPathScript = tInstallHelper:replace_template(
                  string.format('${install_base}/test%02d.lua', uiTestCaseStepCnt)
                )
                local tFileResult, strFileError = pl.utils.writefile(strDestinationPathScript, strTestLua, false)
                if tFileResult~=true then
                  tLog.error('Failed to write the test to "%s": %s', strDestinationPathScript, strFileError)
                  tResult = nil
                  break
                end
              end

            else
              tLog.error('The test %s has no "id" or "file" attribute.', tostring(strTestCaseName))
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



----------------------------------------------------------------------------------------------------------------------


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

-- Register the action for the test installer.
-- It should run before actions with a default level of 50.
t:register_action('install_testcases', actionTestInstaller, t, '${prj_root}', 40)


return tResult
