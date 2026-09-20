{
  app = {
    version = "3.6.0";
    tag = "v3.6.0";
    rev = "31239fa986afb91a15e039e1a9a64ed5a2d6fa12";
    hash = "sha256-hW3CxU28l7zPeUD/NMwHzbugd/wR2FpuE3bAmxu54qs=";
  };

  compatibility = {
    tokenizers = "0.22.2";
    onnxruntime = "1.28.0";
  };

  models = {
    release = "v5.0.0-model";
    dclapRelease = "v1";
    saeRelease = "v1";
  };

  python = {
    googleGenai = {
      version = "1.57.0";
      tag = "v1.57.0";
      rev = "28bd0e832ab55facc81c0ef72567da6d83b6f308";
      hash = "sha256-hDoiUOghzgPHfNh26Yz9gHkyiez6B2QfbboN8uc+Smc=";
    };

    huggingfaceHub = {
      version = "0.36.2";
      tag = "v0.36.2";
      rev = "664c484e261175deeb80c2aa3b525457a1f6fa5c";
      hash = "sha256-cUp5Mm8vgJI/0N/9inQVedGWRde8lioduFoccq6b7UE=";
    };

    mistralai = {
      version = "1.12.4";
      tag = "v1.12.4";
      rev = "c3f22d3c9bf7697f234872e34544eb6f9cdf3feb";
      hash = "sha256-gkxjEVLsW8mC94lk0DwC7KWJDskMUMl3AqCjEvmyEGg=";
    };

    transformers = {
      version = "4.57.6";
      tag = "v4.57.6";
      rev = "753d61104116eefc8ffc977327b441ee0c8d599f";
      hash = "sha256-a78ornUAYlOpr30iFdq1oUiWQTm6GeT0iq8ras5i3DQ=";
      upstreamTokenizersRequirement = "tokenizers>=0.22.0,<=0.23.0";
      tokenizersRequirement = "tokenizers>=0.22.0,<=0.23.2";
    };
  };
}
