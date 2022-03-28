module Main (main) where

#if PROFILE_RUNTIME

import Criterion.Main

import qualified Experiment.SR_Construct.Sized.R010
import qualified Experiment.SR_Construct.Sized.R020
import qualified Experiment.SR_Construct.Sized.R030
import qualified Experiment.SR_Construct.Sized.R040
import qualified Experiment.SR_Construct.Sized.R050
-- import qualified Experiment.SR_Construct.Sized.R060
-- import qualified Experiment.SR_Construct.Sized.R070
-- import qualified Experiment.SR_Construct.Sized.R080
-- import qualified Experiment.SR_Construct.Sized.R090
-- import qualified Experiment.SR_Construct.Sized.R100

main :: IO ()
main = defaultMain [
      bgroup "SR_Construct" [
          bench "010" $ whnf Experiment.SR_Construct.Sized.R010.record 0
        , bench "020" $ whnf Experiment.SR_Construct.Sized.R020.record 0
        , bench "030" $ whnf Experiment.SR_Construct.Sized.R030.record 0
        , bench "040" $ whnf Experiment.SR_Construct.Sized.R040.record 0
        , bench "050" $ whnf Experiment.SR_Construct.Sized.R050.record 0
--        , bench "060" $ whnf Experiment.SR_Construct.Sized.R060.record 0
--        , bench "070" $ whnf Experiment.SR_Construct.Sized.R070.record 0
--        , bench "080" $ whnf Experiment.SR_Construct.Sized.R080.record 0
--        , bench "090" $ whnf Experiment.SR_Construct.Sized.R090.record 0
--        , bench "100" $ whnf Experiment.SR_Construct.Sized.R100.record 0
        ]
    ]

#else

main :: IO ()
main = return ()

#endif