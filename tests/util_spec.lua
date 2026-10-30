local loader = require("tests.loader")

describe("Util", function()
  local ns

  before_each(function()
    ns = loader.load({ "Core/Util.lua" })
  end)

  it("pattern from upgrade format", function()
    local p = ns.Util.FormatToPattern("Upgrade Level: %s %d/%d")
    assert.same({ "Hero", "4", "6" }, { ("Upgrade Level: Hero 4/6"):match(p) })
    assert.is_nil(("  Upgrade Level: Hero 4/6"):match(p))
    assert.is_nil(("Upgrade Level: Hero 4/6 extra"):match(p))
  end)

  it("escapes magic chars", function()
    local p = ns.Util.FormatToPattern("a.b %d%%")
    assert.equals("5", ("a.b 5%"):match(p))
    assert.is_nil(("axb 5%"):match(p))
    local q = ns.Util.FormatToPattern("(x)[y]+-*?^$")
    assert.truthy(("(x)[y]+-*?^$"):match(q))
  end)

  it("parses link", function()
    local link = "|cffa335ee|Hitem:212345:7000::213:0:0::1234:80:::::::|h[Some Item]|h|r"
    assert.same({ itemID = 212345, enchantID = 7000, gems = { 0, 213, 0, 0 } }, ns.Util.ParseItemLink(link))
  end)

  it("parses a bare link and rejects non-links", function()
    assert.same({ itemID = 5, enchantID = 0, gems = { 0, 0, 0, 0 } }, ns.Util.ParseItemLink("|Hitem:5|h[X]|h"))
    assert.is_nil(ns.Util.ParseItemLink("|Hspell:5|h[X]|h"))
    assert.is_nil(ns.Util.ParseItemLink(nil))
  end)

  it("Age buckets", function()
    local age = ns.Util.Age
    assert.equals("just now", age(0))
    assert.equals("just now", age(59))
    assert.equals("1m ago", age(60))
    assert.equals("5m ago", age(5 * 60 + 30))
    assert.equals("59m ago", age(3599))
    assert.equals("1h ago", age(3600))
    assert.equals("3h ago", age(3 * 3600))
    assert.equals("23h ago", age(86399))
    assert.equals("1d ago", age(86400))
    assert.equals("2d ago", age(2 * 86400 + 5))
    assert.equals("just now", age(-5))
  end)
end)
