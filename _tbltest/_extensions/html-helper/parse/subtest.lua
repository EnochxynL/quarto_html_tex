if FORMAT == "html" then
  return { { Pandoc = function(doc)
    io.stderr:write("SUBDIR FILTER RAN\n")
    return doc
  end } }
end
