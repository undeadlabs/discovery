guard :elixir, all_on_start: false do
  watch(%r{^test/(.*)_test\.exs})
  watch(%r{^integration/(.*)_test\.exs})
  watch(%r{^lib/(.+)\.ex$})           { |m| "test/#{m[1]}_test.exs" }
  watch(%r{^test/test_helper.exs$})   { "test" }
end
