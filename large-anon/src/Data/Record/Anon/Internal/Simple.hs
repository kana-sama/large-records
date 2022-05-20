{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE KindSignatures        #-}
{-# LANGUAGE MonoLocalBinds        #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE RecordWildCards       #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE UndecidableInstances  #-}

-- | Simple interface to the anonymous records library
--
-- This module defines a type @Record r@ such that, for example,
--
-- > Record '[ '("a", Bool), '("b", Char) ]
--
-- is the type of records with two fields @a@ and @b@, of types @Bool@ and
-- @Char@ respectively. The difference between the simple interface and the
-- advanced interface is that the advanced interface defines a type
--
-- > Record f '[ '("a", Bool), '("b", Char) ]
--
-- In this case, fields @a@ and @b@ have type @f Bool@ and @f Char@ instead.
-- See "Data.Record.Anonymous.Advanced" for details.
--
-- NOTE: We do not offer a set of combinators in the simple interface, as these
-- are not likely to be very useful. In the rare cases that they are needed,
-- users should use 'toAdvanced'/'fromAdvanced' to temporary use the advanced
-- API for these operations.
--
-- This module is intended for qualified import.
--
-- > import Data.Record.Anonymous.Simple (Record)
-- > import qualified Data.Record.Anonymous.Simple as Anon
module Data.Record.Anon.Internal.Simple (
    Record -- opaque
    -- * Basic API
  , Field -- opaque
  , empty
  , insert
  , insertA
  , get
  , set
  , merge
  , lens
  , project
  , inject
  , applyPending
    -- * Constraints
  , RecordConstraints
    -- * Interop with the advanced interface
  , toAdvanced
  , fromAdvanced
  , sequenceA
    -- * Support for @typelet@
  , letRecordT
  , letInsertAs
  ) where

import Prelude hiding (sequenceA)

import Data.Aeson (ToJSON(..), FromJSON(..))
import Data.Bifunctor
import Data.Record.Generic
import Data.Record.Generic.Eq
import Data.Record.Generic.JSON
import Data.Record.Generic.Show
import Data.Tagged
import GHC.Exts
import GHC.OverloadedLabels
import GHC.Records.Compat
import GHC.TypeLits
import TypeLet
import Data.Primitive.SmallArray

import qualified Optics.Core as Optics

import Data.Record.Anon.Plugin.Internal.Runtime

import Data.Record.Anon.Internal.Advanced (Field(..))

import qualified Data.Record.Anon.Internal.Advanced as A

{-------------------------------------------------------------------------------
  Definition
-------------------------------------------------------------------------------}

-- | Anonymous record
--
-- A @Record r@ has a field @n@ of type @x@ for every @(n := x)@ in @r@.
--
-- To construct a 'Record', use 'Data.Record.Anon.Simple.insert' and
-- 'Data.Record.Anon.Simple.empty', or use the @ANON@ syntax. See
-- 'Data.Record.Anon.Simple.insert' for examples.
--
-- To access fields of the record, either use the 'GHC.Records.Compat.HasField'
-- instances (possibly using the @record-dot-preprocessor@), or using
-- 'Data.Record.Anon.Simple.get' and 'Data.Record.Anon.Simple.set'.
--
-- Remember to enable the plugin when working with anonymous records:
--
-- > {-# OPTIONS_GHC -fplugin=Data.Record.Anon.Plugin #-}
--
-- NOTE: For some applications it is useful to have an additional functor
-- parameter @f@, so that every field has type @f x@ instead.
-- See "Data.Record.Anon.Advanced".
newtype Record r = SimpleRecord { toAdvanced :: A.Record I r }

{-------------------------------------------------------------------------------
  Interop with advanced API
-------------------------------------------------------------------------------}

fromAdvanced :: A.Record I r -> Record r
fromAdvanced = SimpleRecord

sequenceA :: Applicative m => A.Record m r -> m (Record r)
sequenceA = fmap fromAdvanced . A.sequenceA'

{-------------------------------------------------------------------------------
  Basic API
-------------------------------------------------------------------------------}

empty :: Record '[]
empty = fromAdvanced $ A.empty

insert :: Field n -> a -> Record r -> Record (n := a : r)
insert n x = fromAdvanced . A.insert n (I x) . toAdvanced

insertA ::
     Applicative m
  => Field n -> m a -> m (Record r) -> m (Record (n := a : r))
insertA f x r = insert f <$> x <*> r

merge :: Record r -> Record r' -> Record (Merge r r')
merge r r' = fromAdvanced $ A.merge (toAdvanced r) (toAdvanced r')

lens :: SubRow r r' => Record r -> (Record r', Record r' -> Record r)
lens =
      bimap fromAdvanced (\f -> fromAdvanced . f . toAdvanced)
    . A.lens
    . toAdvanced

project :: SubRow r r' => Record r -> Record r'
project = fst . lens

inject :: SubRow r r' => Record r' -> Record r -> Record r
inject small = ($ small) . snd . lens

applyPending :: Record r -> Record r
applyPending = fromAdvanced . A.applyPending . toAdvanced

{-------------------------------------------------------------------------------
  HasField
-------------------------------------------------------------------------------}

instance HasField  n            (A.Record I r) (I a)
      => HasField (n :: Symbol) (    Record   r)    a where
  hasField = aux . hasField @n . toAdvanced
    where
      aux :: (I a -> A.Record I r, I a) -> (a -> Record r, a)
      aux (setX, x) = (fromAdvanced . setX . I, unI x)

instance Optics.LabelOptic n Optics.A_Lens (A.Record I r) (A.Record I r) (I a) (I a)
      => Optics.LabelOptic n Optics.A_Lens (    Record   r) (    Record   r)    a     a where
  labelOptic = toAdvanced Optics.% fromLabel @n Optics.% fromI
    where
      toAdvanced :: Optics.Iso' (Record r) (A.Record I r)
      toAdvanced = Optics.coerced

      fromI :: Optics.Iso' (I a) a
      fromI = Optics.coerced

-- | Get field from the record
--
-- This is just a wrapper around 'getField'.
get :: forall n r a. RowHasField n r a => Field n -> Record r -> a
get (Field _) = getField @n @(Record r)

-- | Update field in the record
--
-- This is just a wrapper around 'setField'.
set :: forall n r a. RowHasField n r a => Field n -> a -> Record r -> Record r
set (Field _) = flip (setField @n @(Record r))

{-------------------------------------------------------------------------------
  Constraints
-------------------------------------------------------------------------------}

class    (AllFields r c, KnownFields r) => RecordConstraints r c
instance (AllFields r c, KnownFields r) => RecordConstraints r c

{-------------------------------------------------------------------------------
  Generics

  We define 'dict' and 'metadata' directly rather than going through the
  instance for 'A.Record'; we /could/ do that, but it's hassle and doesn't
  really buy us anything.
-------------------------------------------------------------------------------}

recordConstraints :: forall r c.
     RecordConstraints r c
  => Proxy c -> Rep (Dict c) (Record r)
recordConstraints _ = Rep $
    aux <$> proxy fieldDicts (Proxy @r)
  where
    aux :: DictAny c -> Dict c Any
    aux DictAny = Dict

instance KnownFields r => Generic (Record r) where
  type Constraints (Record r) = RecordConstraints r
  type MetadataOf  (Record r) = SimpleFieldTypes r

  from     = fromAdvancedRep . from . toAdvanced
  to       = fromAdvanced    . to   . toAdvancedRep
  dict     = recordConstraints
  metadata = const recordMetadata

fromAdvancedRep :: Rep I (A.Record I r) -> Rep I (Record r)
fromAdvancedRep = noInlineUnsafeCo

toAdvancedRep :: Rep I (Record r) -> Rep I (A.Record I r)
toAdvancedRep = noInlineUnsafeCo

recordMetadata :: forall r. KnownFields r => Metadata (Record r)
recordMetadata = Metadata {
      recordName          = "Record"
    , recordConstructor   = "Record"
    , recordSize          = length fields
    , recordFieldMetadata = Rep $ smallArrayFromList fields
    }
  where
    fields :: [FieldMetadata Any]
    fields = fieldMetadata (Proxy @r)

{-------------------------------------------------------------------------------
  Instances

  As for the generic instances, we make no attempt to go through the advanced
  API here, as it's painful for little benefit.
-------------------------------------------------------------------------------}

instance RecordConstraints r Show => Show (Record r) where
  showsPrec = gshowsPrec

instance RecordConstraints r Eq => Eq (Record r) where
  (==) = geq

instance ( RecordConstraints r Eq
         , RecordConstraints r Ord
         ) => Ord (Record r) where
  compare = gcompare

instance RecordConstraints r ToJSON => ToJSON (Record r) where
  toJSON = gtoJSON

instance RecordConstraints r FromJSON => FromJSON (Record r) where
  parseJSON = gparseJSON

{-------------------------------------------------------------------------------
  Support for @typelet@
-------------------------------------------------------------------------------}

-- | Introduce type variable for a row
letRecordT :: forall r.
     (forall r'. Let r' r => Proxy r' -> Record r)
  -> Record r
letRecordT f = letT' (Proxy @r) f

-- | Insert field into a record and introduce type variable for the result
letInsertAs :: forall r r' n a.
     Proxy r     -- ^ Type of the record we are constructing
  -> Field n     -- ^ New field to be inserted
  -> a           -- ^ Value of the new field
  -> Record r'   -- ^ Record constructed so far
  -> (forall r''. Let r'' (n := a : r') => Record r'' -> Record r)
                 -- ^ Assign type variable to new partial record, and continue
  -> Record r
letInsertAs _ n x r = letAs' (insert n x r)

