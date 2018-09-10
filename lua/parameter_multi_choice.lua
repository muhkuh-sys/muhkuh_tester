-- Create the parameter class.
local class = require 'pl.class'
local Parameter = require 'parameter'
local Parameter_MultiChoice = class(Parameter)


function Parameter_MultiChoice:_init(strOwner, strName, strHelp, tLogWriter, strLogLevel)
  self:super(strOwner, strName, strHelp, tLogWriter, strLogLevel)

  self.atConstraint = nil
end


function Parameter_MultiChoice:constraint(tConstraint)
  local atChoices
  if type(tConstraint)=='table' then
    -- Check if all indices are non-0 numbers and the values in the table are strings.
    for tKey, tValue in pairs(tConstraint) do
      if type(tKey)~='number' then
        self.tLog.error('The constraint table contains a non-numeric key.')
        error('invalid constraint')
      end
      local lNum, fNum = math.modf(tKey)
      if fNum~=0 then
        self.tLog.error('The constraint table contains a non-integer number as a key.')
        error('invalid constraint')
      end
      if lNum==0 then
        self.tLog.error('The constraint table contains a 0 as a key.')
        error('invalid constraint')
      end
    end

    atChoices = {}
    for _, tChoice in ipairs(tConstraint) do
      strChoice = self.pl.stringx.strip(tostring(tChoice))
      if strChoice~='' then
        if self.pl.tablex.find(atChoices, strChoice)~=nil then
          self.tLog.error('The constraints contains more than one entry of "%s".', strChoice)
          error('invalid constraint')
        end
        table.insert(atChoices, strChoice)
      end
    end

    if table.maxn(atChoices)==0 then
      self.tLog.error('The constraint table contains no values.')
      error('invalid constraint')
    end
  elseif type(tConstraint)=='string' then
    -- Split the string by comma.
    local astrElements = self.pl.stringx.split(tConstraint, ',')

    atChoices = {}
    for _, strChoice in ipairs(astrElements) do
      strChoice = self.pl.stringx.strip(strChoice)
      if strChoice~='' then
        table.insert(atChoices, strChoice)
      end
    end

    if table.maxn(atChoices)==0 then
      self.tLog.error('The constraint string contains no values.')
      error('invalid constraint')
    end
  else
    self.tLog.error('The constraint must be a table or a string. Here it is of type "%s".', type(tConstraint))
    error('invalid constraint')
  end


  self.atConstraint = atChoices

  return self
end


function Parameter_MultiChoice:__validate(tValue)
  local fIsValid = true
  local tValidatedValue
  local strMessage

  local astrRawValues = self.pl.stringx.split(tostring(tValue), ',')
  local astrValues = {}
  for _, strValue in ipairs(astrRawValues) do
    strValue = self.pl.stringx.strip(strValue)
    if strValue~='' then
      table.insert(astrValues, strValue)
    end
  end
  if table.maxn(astrValues)==0 then
    fIsValid = false
    strMessage = 'No value selected.'
  elseif self.atConstraint==nil then
    fIsValid = false
    strMessage = 'Unable to validate the parameter as a multi choice. No constraint is set.'
  else
    for _, strValue in ipairs(astrValues) do
      if self.pl.tablex.find(self.atConstraint, strValue)==nil then
        fIsValid = false
        strMessage = string.format('The value %s is not in the list of allowed values, which is %s.', strValue, table.concat(self.atConstraint, ', '))
      end
    end
    if fIsValid==true then
      tValidatedValue = astrValues
    end
  end

  return fIsValid, tValidatedValue, strMessage
end


return Parameter_MultiChoice
