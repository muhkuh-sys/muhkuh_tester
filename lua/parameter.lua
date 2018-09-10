-- Create the parameter class.
local class = require 'pl.class'
local Parameter = class()

function Parameter:_init(strOwner, strName, strHelp, tLogWriter, strLogLevel)
  -- The owner must be a string. It must not be empty.
  if type(strOwner)~='string' then
    error('The argument "strOwner" must be a string.')
  elseif string.len(strOwner)==0 then
    error('The argument "strOwner" must not be empty.')
  end
  self.strOwner = strOwner

  -- The name must be a string. It must not be empty.
  if type(strName)~='string' then
    error('The argument "strName" must be a string.')
  elseif string.len(strName)==0 then
    error('The argument "strName" must not be empty.')
  end
  self.strName = strName

  -- Create an ID from the owner and the name.
  local strID = string.format('%s:%s', strOwner, strName)
  self.strID = strID

  -- Create a new log target for the testcase.
  local tLogWriterParameter = require 'log.writer.prefix'.new(
    string.format('[Param %s] ', strID),
    tLogWriter
  )
  self.tLog = require 'log'.new(
    -- maximum log level
    strLogLevel,
    tLogWriterParameter,
    -- Formatter
    require 'log.formatter.format'.new()
  )

  -- The help must be a string. It can be empty.
  if strHelp==nil then
    strHelp = ''
  elseif type(strHelp)~='string' then
    error('The argument "strHelp" must be a string or nil.')
  end
  self.strHelp = strHelp

  -- Set the rest of the parameter to default values.
  self.fHasDefaultValue = false
  self.tDefaultValue = nil
  self.fRequired = false
  self.fnConstraint = nil

  self.fHasValue = false
  self.tValue = nil

  self.fIsValidated = false
  self.tValidatedValue = nil

  self.atConnections = {}
end


function Parameter:default(tDefaultValue)
  self.tDefaultValue = tDefaultValue
  self.fHasDefaultValue = true

  return self
end


function Parameter:required(fRequired)
  -- Convert the input to a boolean.
  if fRequired then
    fRequired = true
  else
    fRequired = false
  end

  self.fRequired = fRequired

  return self
end


function Parameter:constraint(fnConstraint)
  if fnConstraint~=nil and type(fnConstraint)~='function' then
    self.tLog.error('The constraint must be nil or a function.')
    error('invalid constraint')
  end
  self.fnConstraint = fnConstraint

  return self
end


function Parameter:has_value()
  return self.fHasValue
end


function Parameter:__set(tValue)
  self.tValue = tValue
  self.fHasValue = true
  self.fIsValidated = false
end


function Parameter:set(tValue, atAlreadyProcessed)
  atAlreadyProcessed = atAlreadyProcessed or {}

  if atAlreadyProcessed[self]==nil then
    self.tLog.debug('Set to %s.', tostring(tValue))

    -- Set the value in the local object.
    self:__set(tValue)

    -- Add me to the list of already processed parameters.
    atAlreadyProcessed[self] = true

    -- Propagate the value to all connections if they are not in the list of already processed items.
    for tParam, _ in pairs(self.atConnections) do
      if atAlreadyProcessed[tParam]==nil then
        tParam:set(tValue, atAlreadyProcessed)
      end
    end
  else
    self.tLog.debug('Ignoring set, already done.')
  end
end


function Parameter:get_raw()
  local tValue

  if self:has_value() then
    tValue = self.tValue
  elseif self.fHasDefaultValue then
    tValue = self.tDefaultValue
  else
    self.tLog.error('No value and no default value present.')
    error('get_raw on unset parameter')
  end

  return tValue
end


function Parameter:get()
  local tValue

  if self.fIsValidated~=true then
    self.tLog.error('Failed to get the validated value as the parameter is not validated yet.')
    error('not validated')
  else
    tValue = self.tValidatedValue
  end

  return tValue
end


function Parameter:connect(tParameter)
  -- Parameters can only be connected to parameters.
  if Parameter:class_of(tParameter)~=true then
    self.tLog.error('Connections can only be established between 2 parameters.')
    error('invalid parameter for connect')
  end

  -- Get the ID of the parameter to connect to.
  local strOtherID = tParameter.strID

  -- Is the parameter already in the list?
  if self.atConnections[tParameter]~=nil then
    self.tLog.debug('Already connected to %s.', strOtherID)
  else
    self.tLog.debug('Connecting to %s.', strOtherID)

    if self:has_value()==true and tParameter:has_value()==true and self:get_raw()~=tParameter:get_raw() then
      self.tLog.error('Can not connect to %s. both sides have values and they differ.', strOtherID)
      error('connect failed: both sides set to different values')
    end

    -- Add the other side to my list of connections.
    self.atConnections[tParameter] = true

    -- Connect the other side to ourself.
    tParameter:connect(self)

    -- Connect the other side to all of our connections.
    for tConnection, _ in pairs(self.atConnections) do
      if tConnection~=tParameter then
        tParameter:connect(tConnection)
      end
    end

    -- Get the value from the other side if there is a value and we do not have one yet.
    if self:has_value()==false and tParameter:has_value()==true then
      local tValue = tParameter:get_raw()
      self.tLog.debug('Initialize value from %s with %s .', strOtherID, tostring(tValue))
      self:__set(tValue)
    end
  end

  return self
end


function Parameter:validate()
  -- Be optimistic.
  local fIsValid = true
  local tValue = nil
  local strMessage = nil
  local fnValidate = self.__validate
  local fnConstraint = self.fnConstraint

  -- Is some value set?
  if self.fHasDefaultValue~=true and self.fHasValue~=true then
    -- This is only an error if the value is required.
    if self.fRequired==true then
      fIsValid = false
      strMessage = 'The parameter is required, but no value and no default value is set.'
    else
      self.fIsValidated = true
      self.tValidatedValue = nil
    end

  else
    -- Get the value if it is set. Fallback to the default value.
    tValue = self.tValue
    if self.fHasValue~=true then
      tValue = self.tDefaultValue
    end

    if fnValidate~=nil then
      -- Check the value with the validate function.
      fIsValid, tValue, strMessage = fnValidate(self, tValue)
      if fIsValid~=true then
        self.tLog.debug('The validate function complained with the message "%s".', tostring(strMessage))
      end
    end

    if fIsValid==true and fnConstraint~=nil then
      -- Check the value with the constraint function.
      fIsValid, tValue, strMessage = fnConstraint(tValue)
      if fIsValid~=true then
        self.tLog.debug('The constraint function complained with the message "%s".', tostring(strMessage))
      end
    end

    self.fIsValidated = true
    self.tValidatedValue = tValue
  end

  return fIsValid, strMessage
end


function Parameter:dump()
  local tLog = self.tLog
  tLog.debug('Help text: "%s".', self.strHelp)
  tLog.debug('fHasDefaultValue: %s', tostring(self.fHasDefaultValue))
  tLog.debug('tDefaultValue: %s', tostring(self.tDefaultValue))
  tLog.debug('type of tDefaultValue: %s', type(self.tDefaultValue))
  tLog.debug('fRequired: %s', tostring(self.fRequired))
  tLog.debug('fnConstraint: %s', tostring(self.fnConstraint))
  tLog.debug('tValue: %s', tostring(self.tValue))
  tLog.debug('type of tValue: %s', type(self.tValue))
  tLog.debug('fHasValue: %s', tostring(self.fHasValue))
  for tParameter, _ in pairs(self.atConnections) do
    tLog.debug('connected to %s', tParameter.strID)
  end
end


return Parameter
