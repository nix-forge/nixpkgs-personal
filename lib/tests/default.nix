_:
let
  render = import ../render-text.nix;
  fixture = ./template.txt;
in
{
  render = {
    testReplacement = {
      expr = render fixture {
        name = "Ada";
        optional = "done";
      };
      expected = "Hello Ada! done Ada\n";
    };
    testLiteralMarker = {
      expr = render fixture {
        name = "Ada";
        optional = null;
      };
      expected = "Hello Ada! @optional@ Ada\n";
    };
    testMissing = {
      expr = render fixture { name = "Ada"; };
      expectedError.type = "ThrownError";
      expectedError.msg = ".*missing replacements.*optional.*";
    };
    testUnused = {
      expr = render fixture {
        name = "Ada";
        optional = null;
        unused = "extra";
      };
      expectedError.type = "ThrownError";
      expectedError.msg = ".*unused replacements.*unused.*";
    };
    testInvalidName = {
      expr = render fixture {
        name = "Ada";
        optional = null;
        "bad-name" = "extra";
      };
      expectedError.type = "ThrownError";
      expectedError.msg = ".*invalid placeholder name.*";
    };
    testStringContext = {
      expr = builtins.hasContext (
        render fixture {
          name = builtins.toFile "library-test-input" "value";
          optional = null;
        }
      );
      expected = true;
    };
    testPath = {
      expr = render fixture {
        name = fixture;
        optional = null;
      };
      expected = "Hello ${fixture}! @optional@ ${fixture}\n";
    };
  };
}
