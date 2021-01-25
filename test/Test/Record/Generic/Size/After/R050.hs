{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -fplugin=GhcDump.Plugin #-}

module Test.Record.Generic.Size.After.R050 where

import Data.Aeson (ToJSON(..))

import Data.Record.Generic
import Data.Record.Generic.JSON
import Data.Record.Generic.TH

import Test.Record.Generic.Size.Infra

largeRecord defaultOptions (recordOfSize 50)

instance ToJSON R where
  toJSON = gtoJSON