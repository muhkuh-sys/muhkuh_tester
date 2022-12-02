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
--
-- ActionDocBuilder
--

local function __lustache_runInSandbox(atValues, strCode)
  local compat = require 'pl.compat'

  -- Create a sandbox.
  local atEnv = {
    ['error']=error,
    ['ipairs']=ipairs,
    ['next']=next,
    ['pairs']=pairs,
    ['print']=print,
    ['select']=select,
    ['tonumber']=tonumber,
    ['tostring']=tostring,
    ['type']=type,
    ['math']=math,
    ['string']=string,
    ['table']=table
  }
  for strKey, tValue in pairs(atValues) do
    atEnv[strKey] = tValue
  end
  local tFn, strError = compat.load(strCode, 'parser code', 't', atEnv)
  if tFn==nil then
    return nil, string.format('Parse error in code "%s": %s', strCode, tostring(strError))
  else
    local fRun, fResult = pcall(tFn)
    if fRun==false then
      return nil, string.format('Failed to run the code "%s": %s', strCode, tostring(fResult))
    else
      return fResult
    end
  end
end



local function __lustache_createView(atConfiguration, atVariables, atExtension)
  local tablex = require 'pl.tablex'

  -- Create a new copy of the variables.
  local atView = tablex.deepcopy(atVariables)

  -- Add the commom methods.
  atView['if'] = function(text, render, context)
    local strResult
    -- Extract the condition.
    local strCondition, strText = string.match(text, '^%{%{([^}]+)%}%}(.*)')
    local strCode = 'return ' .. strCondition
    local fResult, strConditionError = __lustache_runInSandbox(context, strCode)
    if fResult==nil then
      strResult = string.format('ERROR in if condition: %s', strConditionError)
    else
      if fResult==true then
        strResult = render(strText)
      end
    end
    return strResult
  end

  atView['import'] = function(text, render, context)
    local path = require 'pl.path'
    local strFile = render(text)
    -- Append the filename to the list of files.
    local strImportFilename = path.abspath(strFile, path.dirname(atConfiguration.strCurrentDocument))
    if string.sub(strImportFilename, -string.len(atConfiguration.strSuffix))==atConfiguration.strSuffix then
      table.insert(atConfiguration.atFiles, {
        path = strImportFilename,
        view = context
      })
    end
    local strFilteredFilename = string.sub(
      strImportFilename,
      1,
      string.len(strImportFilename) - string.len(atConfiguration.strSuffix)
    ) .. atConfiguration.ext
    local strResult = string.format(
      ':imagesdir: %s\ninclude::%s[]',
      path.dirname(strImportFilename),
      strFilteredFilename
    )

    return strResult
  end

  if atExtension~=nil then
    tablex.update(atView, atExtension)
  end

  return atView
end



local function actionDocBuilder(tInstallHelper)
  local tResult = true
  local pl = tInstallHelper.pl
  local tLog = tInstallHelper.tLog

  local atConfiguration = {
    root = 'main',
    ext = '.asciidoc',
    strSuffix = '.mustache.asciidoc',
    strCurrentDocument = nil,
    atFiles = {}
  }

  local atRootView = {
    test_steps = {}
  }

  local strTestsFile = 'tests.xml'
  if pl.path.exists(strTestsFile)~=strTestsFile then
    tLog.error('The test configuration file "%s" does not exist.', strTestsFile)
    tResult = nil
  elseif pl.path.isfile(strTestsFile)~=true then
    tLog.error('The path "%s" is no regular file.', strTestsFile)
    tResult = nil
  else
    tLog.debug('Parsing tests file "%s".', strTestsFile)
    local tTestDescription = require 'test_description'(tLog)
    local tParseResult = tTestDescription:parse(strTestsFile)
    if tParseResult~=true then
      tLog.error('Failed to parse the test configuration file "%s".', strTestsFile)
      tResult = nil
    else
      atRootView.test_title = tTestDescription:getTitle()
      atRootView.test_subtitle = tTestDescription:getSubtitle()

      -- Copy all documentation links.
      atRootView.documentation_links = tTestDescription:getDocuments()

      -- Collect the documentation for all test cases.
      local uiTestCaseStepMax = tTestDescription:getNumberOfTests()
      for uiTestCaseStepCnt = 1,uiTestCaseStepMax do
        local strTestCaseName = tTestDescription:getTestCaseName(uiTestCaseStepCnt)
        local strDocPath
        local strParameterPath

        local strTestCaseId = tTestDescription:getTestCaseId(uiTestCaseStepCnt)
        local strTestCaseFile = tTestDescription:getTestCaseFile(uiTestCaseStepCnt)
        if strTestCaseId~=nil then
          -- Get the path where the source documentation is copied to.
          strDocPath = pl.path.join(
            tInstallHelper:replace_template('${build_doc}'),
            strTestCaseId,
            'teststep' .. atConfiguration.strSuffix
          )
          tLog.debug('Looking for documentation in "%s".', strDocPath)
          if pl.path.exists(strDocPath)~=strDocPath then
            tLog.warning('The test %s has no documentation.', strTestCaseName)
            strDocPath = nil
          end

          -- Get the installation path of the parameter file.
          strParameterPath = pl.path.join(
            tInstallHelper:replace_template('${install_base}/parameter/'),
            strTestCaseId .. '.json'
          )
          tLog.debug('Looking for parameter in "%s".', strParameterPath)
          if pl.path.exists(strParameterPath)~=strParameterPath then
            tLog.warning('The test %s has no parameter file.', strTestCaseName)
            strParameterPath = nil
          end
        elseif strTestCaseFile~=nil then

          strDocPath = tTestDescription:getTestCaseDoc(uiTestCaseStepCnt)
          if strDocPath==nil or strDocPath=='' then
            tLog.warning('The test %s has no documentation.', strTestCaseName)
            strDocPath = nil
          elseif pl.path.exists(strDocPath)~=strDocPath then
            tLog.warning('The specified documentation "%s" for test %s does not exist.', strDocPath, strTestCaseName)
            strDocPath = nil
          else
            tLog.debug('Found documentation in "%s".', strDocPath)
          end


        else
          tLog.error('The test %s has no "id" or "file" attribute.', strTestCaseName)
          tResult = nil
          break

        end

        local tParameter = {}
        local tViewAttr = {
          docfile = strDocPath,
          name = strTestCaseName,
          parameter = tParameter
        }
        -- Set all default parameter.
        if strParameterPath~=nil then
          -- Try to read the file.
          local strParameterData, strParameterReadError = pl.utils.readfile(strParameterPath, false)
          if strParameterData==nil then
            tLog.error(
              'Failed to read the parameter file "%s" for test %s: %s',
              strParameterPath,
              strTestCaseName,
              strParameterReadError
            )
          else
            -- Read the parameter JSON and extract all default values.
            local cjson = require 'cjson.safe'
            -- Activate "array" support. This is necessary for the "required" attribute in schemata.
            cjson.decode_array_with_array_mt(true)
            -- Read the parameter file.
            local tParameterData, strParameterParseError = cjson.decode(strParameterData)
            if tParameterData==nil then
              tLog.error(
                'Failed to parse the parameter file "%s" for test %s: %s',
                strParameterPath,
                strTestCaseName,
                strParameterParseError
              )
            else
              -- TODO: validate the parameter data with a schema?

              -- Iterate over all parameters and add them with optional default values to the lookup table.
              for _, tAttr in ipairs(tParameterData.parameter) do
                local strName = tAttr.name
                local tP = {
                  name = strName
                }
                local strDefault = tAttr.default
                if strDefault~=nil then
                  tP.type = 'default'
                  tP.value = strDefault
                  tP.default = strDefault
                end
                tParameter[strName] = tP
              end
            end
          end
        end
        -- Add all parameter from the test description.
        local atTestCaseParameter = tTestDescription:getTestCaseParameters(uiTestCaseStepCnt)
        for _, tEntry in ipairs(atTestCaseParameter) do
          local strName = tEntry.name
          local tP = tParameter[strName]
          if tP==nil then
            tP = {
              name = strName
            }
            tParameter[strName] = tP
          end
          if tEntry.value~=nil then
            tP.type = 'constant'
            tP.value = tEntry.value
          elseif tEntry.connection~=nil then
            tP.type = 'connection'
            tP.value = tEntry.connection
          end
        end

        table.insert(atRootView.test_steps, tViewAttr)
      end
    end
  end

  if tResult==true then
    -- DEBUG: Show the view.
    pl.pretty.dump(atRootView)

    -- Get lustache.
    local lustache = require 'lustache'

    -- Inject the root template.
    table.insert(atConfiguration.atFiles, {
      path = pl.path.join(
        tInstallHelper:replace_template('${build_doc}'),
        atConfiguration.root .. atConfiguration.strSuffix
      ),
      view = atRootView
    })

    while #atConfiguration.atFiles ~= 0 do
      -- Get the first entry from the list.
      local tEntry = table.remove(atConfiguration.atFiles, 1)
      local strTemplateFilename = tEntry.path
      atConfiguration.strCurrentDocument = strTemplateFilename
      tLog.debug('Processing %s ...', strTemplateFilename)
      -- Only process files with the requires suffix.
      if string.sub(strTemplateFilename, -string.len(atConfiguration.strSuffix))==atConfiguration.strSuffix then
        local strTemplate, strTemplateError = pl.utils.readfile(strTemplateFilename, false)
        if strTemplate==nil then
          error(string.format('Failed to read "%s": %s', strTemplateFilename, strTemplateError))
        end

        -- Read an optional view extension.
        local atViewExtension = nil
        local strViewPath = pl.path.join(pl.path.dirname(strTemplateFilename), 'view.lua')
        if pl.path.exists(strViewPath)==strViewPath and pl.path.isfile(strViewPath)==true then
          local strView, strViewError = pl.utils.readfile(strViewPath, false)
          if strView==nil then
            error(string.format('Failed to read "%s": %s', strViewPath, strViewError))
          end
          local strCode = 'return ' .. strView
          local fResult, strError = __lustache_runInSandbox({}, strCode)
          if fResult==nil then
            error(string.format('ERROR in view: %s', tostring(strError)))
          elseif type(fResult)~='table' then
            error(string.format('view returned strange result: %s', tostring(fResult)))
          else
            atViewExtension = fResult
          end
        end

        -- Create a new view.
        local atView = __lustache_createView(atConfiguration, tEntry.view, atViewExtension)

        local strOutput = lustache:render(strTemplate, atView)

        -- Write the output file to the same folder as the input file.
        local strOutputFilename = string.sub(
          strTemplateFilename,
          1,
          string.len(strTemplateFilename) - string.len(atConfiguration.strSuffix)
        ) .. atConfiguration.ext

        pl.utils.writefile(strOutputFilename, strOutput, false)
      end
    end
  end

  if tResult==true then
    -- Create the HTML output folder if it does not exist yet.
    local strHtmlOutputPath = pl.path.join(
      tInstallHelper:replace_template('${build_doc}'),
      'generated',
      'html'
    )

    -- Build the HTML documentation with AsciiDoctor.
    local astrCommandHtml = {
      'asciidoctor',

      -- Generate HTML5.
      '--backend', 'html5',

      -- Create an article.
      '--doctype', 'article',

      -- Enable the "Kroki" extension for diagrams.
      -- TODO: Use a local server.
      '--require', 'asciidoctor-kroki',

      -- Set the output folder.
      string.format('--destination-dir=%s', strHtmlOutputPath),

      -- Set the input document.
      pl.path.join(
        tInstallHelper:replace_template('${build_doc}'),
        atConfiguration.root .. atConfiguration.ext
      )
    }
    local strCommandHtml = table.concat(astrCommandHtml, ' ')
    local tResultHtml = os.execute(strCommandHtml)
    if tResultHtml~=true then
      error(string.format('Failed to generate the HTML documentation with the command "%s".', strCommandHtml))
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

-- Register the action for the documentation.
-- It must run after the finalizer with level 75.
-- It must run before the pack action with level 80.
t:register_action('build_documentation', actionDocBuilder, t, '${prj_root}', 78)


return tResult
