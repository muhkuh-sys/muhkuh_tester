-- Create the parameter class.
local class = require 'pl.class'
local ParameterInstances = class()

function ParameterInstances:_init(strOwner, tLogWriter, strLogLevel)
  self.strOwner = strOwner
  self.tLogWriter = tLogWriter
  self.strLogLevel = strLogLevel

  -- Get all parameter classes.
  self.cP = require 'parameter'
  self.cP_MC = require 'parameter_multi_choice'
  self.cP_SC = require 'parameter_single_choice'
  self.cP_U8 = require 'parameter_uint8'
  self.cP_U16 = require 'parameter_uint16'
  self.cP_U32 = require 'parameter_uint32'
end


function ParameterInstances:P(strName, strHelp)
  return self.cP(self.strOwner, strName, strHelp, self.tLogWriter, self.strLogLevel)
end


function ParameterInstances:MC(strName, strHelp)
  return self.cP_MC(self.strOwner, strName, strHelp, self.tLogWriter, self.strLogLevel)
end


function ParameterInstances:SC(strName, strHelp)
  return self.cP_SC(self.strOwner, strName, strHelp, self.tLogWriter, self.strLogLevel)
end


function ParameterInstances:U8(strName, strHelp)
  return self.cP_U8(self.strOwner, strName, strHelp, self.tLogWriter, self.strLogLevel)
end


function ParameterInstances:U16(strName, strHelp)
  return self.cP_U16(self.strOwner, strName, strHelp, self.tLogWriter, self.strLogLevel)
end


function ParameterInstances:U32(strName, strHelp)
  return self.cP_U32(self.strOwner, strName, strHelp, self.tLogWriter, self.strLogLevel)
end


return ParameterInstances
