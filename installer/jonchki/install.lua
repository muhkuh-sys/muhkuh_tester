local t = ...


local class = require 'pl.class'


----------------------------------------------------------------------------------------------------------------------
--
-- TestParser
--
local TestParser = class()

function TestParser:_init(tLog)
  self.tLog = tLog
end

--- Expat callback function for starting an element.
-- This function is part of the callbacks for the expat parser.
-- It is called when a new element is opened.
-- @param tParser The parser object.
-- @param strName The name of the new element.
function TestParser.__parseTests_StartElement(tParser, strName, atAttributes)
  local aLxpAttr = tParser:getcallbacks().userdata
  local iPosLine, iPosColumn = tParser:pos()

  table.insert(aLxpAttr.atCurrentPath, strName)
  local strCurrentPath = table.concat(aLxpAttr.atCurrentPath, "/")
  aLxpAttr.strCurrentPath = strCurrentPath

  if strCurrentPath=='/MuhkuhTest/Testcase' then
    local strID = atAttributes['id']
    local strFile = atAttributes['file']
    local strTestcaseName = atAttributes['name']
    if (strID==nil or strID=='') and (strFile==nil or strFile=='') then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error(
        'Error in line %d, col %d: one of "id" or "file" must be present, but none found.',
        iPosLine,
        iPosColumn
      )
    elseif (strID~=nil and strID~='') and (strFile~=nil and strFile~='') then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error(
        'Error in line %d, col %d: one of "id" or "file" must be present, but both found.',
        iPosLine,
        iPosColumn
      )
    elseif strTestcaseName==nil or strTestcaseName=='' then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: missing "name".', iPosLine, iPosColumn)
    else
      local tTestCase = {
        id = strID,
        file = strFile,
        name = strTestcaseName,
        parameter = {}
      }
      aLxpAttr.tTestCase = tTestCase
      aLxpAttr.strParameterName = nil
      aLxpAttr.strParameterData = nil
    end

  elseif strCurrentPath=='/MuhkuhTest/Testcase/Parameter' then
    local strParameterName = atAttributes['name']
    if strParameterName==nil or strParameterName=='' then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: missing "name".', iPosLine, iPosColumn)
    else
      aLxpAttr.strParameterName = strParameterName
    end
  end
end



--- Expat callback function for closing an element.
-- This function is part of the callbacks for the expat parser.
-- It is called when an element is closed.
-- @param tParser The parser object.
-- @param strName The name of the closed element.
function TestParser.__parseTests_EndElement(tParser)
  local aLxpAttr = tParser:getcallbacks().userdata
  local iPosLine, iPosColumn = tParser:pos()

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
function TestParser.__parseTests_CharacterData(tParser, strData)
  local aLxpAttr = tParser:getcallbacks().userdata

  if aLxpAttr.strCurrentPath=="/MuhkuhTest/Testcase/Parameter" then
    aLxpAttr.strParameterData = strData
  end
end



function TestParser:parse_tests(strTestsFile)
  local tLog = self.tLog
  local tResult = nil
  local utils = require 'pl.utils'

  -- Read the complete file.
  local strFileData, strError = utils.readfile(strTestsFile)
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
      tLog.error(
        'Failed to parse the test configuration "%s": %s in line %d, column %d, position %d.',
        strTestsFile,
        strMsg,
        uiLine,
        uiCol,
        uiPos
      )
    elseif aLxpAttr.tResult~=true then
      tLog.error('Failed to parse the test configuration.')
    else
      tResult = aLxpAttr.atTestCases
    end
  end

  return tResult
end

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
        local tParser = TestParser(tLog)
        local atTestCases = tParser:parse_tests(strTestsFile)
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
                tLog.error(
                  'The test case install script "%s" for the test %s / %s does not exist.',
                  strInstallScriptPath,
                  tTestCase.id,
                  tTestCase.name
                )
                tResult = nil
                break
              elseif pl.path.isfile(strInstallScriptPath)~=true then
                tLog.error(
                  'The test case install script "%s" for the test %s / %s is no regular file.',
                  strInstallScriptPath,
                  tTestCase.id,
                  tTestCase.name
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
              local strTestTemplate, strTemplateError = pl.utils.readfile(strStarterFile, false)
              if strTestTemplate==nil then
                tLog.error('Failed to open the test template "%s": %s', strStarterFile, strTemplateError)
                tResult = nil
                break
              else
                local astrReplace = {
                  ['ID'] = string.format('%02d', uiTestCaseId),
                  ['NAME'] = strName
                }
                local strTestLua = string.gsub(strTestTemplate, '@([^@]+)@', astrReplace)

                -- Write the test script to the installation base directory.
                local strDestinationPathScript = tInstallHelper:replace_template(
                  string.format('${install_base}/test%02d.lua', uiTestCaseId)
                )
                local tFileResult, strFileError = pl.utils.writefile(strDestinationPathScript, strTestLua, false)
                if tFileResult~=true then
                  tLog.error('Failed to write the test to "%s": %s', strDestinationPathScript, strFileError)
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


----------------------------------------------------------------------------------------------------------------------
--
-- ActionDocBuilder
--


--[[
local function __lustache_checkPaths(strPath)
  local tLog = __atLustacheConfiguration.tLog
  local path = require 'pl.path'
  local strExistingPath
  -- Is the argument an absolute path?
  if path.isabs(strPath)==true then
    if path.exists(strPath)==strPath and path.isfile(strPath)==true then
      tLog.debug('  Absolute path "%s" exists.', strPath)
      strExistingPath = strPath
    else
      tLog.debug('  Absolute path "%s" does not exists.', strPath)
    end
  else
    -- Loop over all include paths in the configuration.
    for _, strIncludePath in ipairs(__atLustacheConfiguration.includes) do
      local strTest = path.join(strIncludePath, strPath)
      if path.exists(strTest)==strTest and path.isfile(strTest)==true then
        tLog.debug('  Found "%s".', strTest)
        strExistingPath = strTest
        break
      else
        tLog.debug('  Not found at "%s".', strTest)
      end
    end
  end

  return strExistingPath
end



local function __lustache_searchFile(strId)
  local tLog = __atLustacheConfiguration.tLog
  tLog.debug('Search file "%s".', tostring(strId))
  -- Does the path exist as it is?
  local strPath = __lustache_checkPaths(strId)
  if strPath==nil then
    local path = require 'pl.path'
    -- Does the ID have an extension?
    local _, strExt = path.splitext(strId)
    if strExt=='' then
      -- The ID has no extension. Append the default one.
      strPath = __lustache_checkPaths(strId .. __atLustacheConfiguration.ext)
    end
  end
  return strPath
end
--]]


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
    local tParser = TestParser(tLog)
    local atTestCases = tParser:parse_tests(strTestsFile)
    if atTestCases==nil then
      tLog.error('Failed to parse the test configuration file "%s".', strTestsFile)
      tResult = nil
    else
      -- Collect the documentation for all test cases.
      for _, tTestCase in ipairs(atTestCases) do
        local strName = tostring(tTestCase.name)
        local strDocPath

        if tTestCase.id~=nil then
          -- Get the path where the source documentation is copied to.
          local strDepackPath = tInstallHelper:replace_template('${build_doc}')
          strDocPath = pl.path.join(strDepackPath, tTestCase.id, 'teststep' .. atConfiguration.strSuffix)
          tLog.debug('Looking for documentation in "%s".', strDocPath)
          if pl.path.exists(strDocPath)~=strDocPath then
            tLog.warning('The test %s has no documentation.', strName)
            strDocPath = nil
          end

        elseif tTestCase.file~=nil then

          strDocPath = tTestCase.doc
          if strDocPath==nil or strDocPath=='' then
            tLog.warning('The test %s has no documentation.', strName)
            strDocPath = nil
          elseif pl.path.exists(strDocPath)~=strDocPath then
            tLog.warning('The specified documentation "%s" for test %s does not exist.', strDocPath, strName)
            strDocPath = nil
          else
            tLog.debug('Found documentation in "%s".', strDocPath)
          end


        else
          tLog.error('The test %s has no "id" or "file" attribute.', strName)
          tResult = nil
          break

        end

        local tParameter = {}
        local tViewAttr = {
          docfile = strDocPath,
          name = strName,
          parameter = tParameter
        }
        for _, tEntry in ipairs(tTestCase.parameter) do
          tParameter[tEntry.name] = tEntry.value
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
