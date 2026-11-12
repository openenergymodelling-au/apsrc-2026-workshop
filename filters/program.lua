-- program.lua
-- Builds the event header, schedule and talk details for both outputs:
--   * PDF (Typst): calls the layout functions in theme/layout.typ
--   * Web (HTML):  writes HTML styled by theme/web.scss
--
-- Data comes from:
--   * schedule.yml (loaded as metadata by _quarto.yml): event details,
--     sessions and talk folders
--   * talks/<session-folder>/*.md: one file per talk (files starting with "_" are skipped)
--
-- Placeholders in the .qmd files:
--   ::: {.program-header}                  -> event header
--   ::: {.program-schedule}                -> event header + schedule
--   ::: {.program-schedule header="false"} -> schedule only
--   ::: {.program-schedule talks-page="talks.html"}
--                                          -> (web) talk titles link to that page
--   ::: {.program-talks}                   -> talk details, grouped by session folder
--   ::: {.todo}                            -> highlighted "to do" box
--
-- If schedule.yml has `draft-notice:`, it's shown above the header (PDF) and
-- at the top of every web page.

local stringify = pandoc.utils.stringify

-- More talks than this in a session -> shown in two columns.
local TWO_COLUMNS_AFTER = 10

-- Metadata helpers -------------------------------------------------------

-- Metadata value -> Inlines, or nil when missing/empty.
local function inlines_or_nil(value)
  if value == nil then return nil end
  local t = pandoc.utils.type(value)
  local inl
  if t == "Inlines" then
    inl = value
  elseif t == "Blocks" then
    inl = pandoc.utils.blocks_to_inlines(value)
  else
    local s = stringify(value)
    if s == "" then return nil end
    inl = pandoc.Inlines(s)
  end
  if #inl == 0 then return nil end
  return inl
end

local function as_list(value)
  if value == nil then return {} end
  if pandoc.utils.type(value) == "List" then return value end
  return { value }
end

local function read_file(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local text = fh:read("a")
  fh:close()
  return text
end

local function sorted_listing(dir)
  local ok, entries = pcall(pandoc.system.list_directory, dir)
  if not ok then return nil end
  table.sort(entries)
  return entries
end

-- Loading the data -------------------------------------------------------
-- Everything is kept as pandoc values here; each writer converts them.

local function load_talk(path, folder, file)
  local doc = pandoc.read(read_file(path), "markdown")
  local m = doc.meta

  local where = folder .. "/" .. file
  if m.speakers and not m.authors then
    quarto.log.warning("program.lua: " .. where .. " uses `speakers:`; rename it to `authors:`")
  end

  -- Authors in author order; one of them presents.
  local authors, presenter = {}, nil
  for _, a in ipairs(as_list(m.authors or m.speakers)) do
    local author = {
      name = inlines_or_nil(a.name),
      honorific = inlines_or_nil(a.honorific),
      affiliation = inlines_or_nil(a.affiliation),
      affiliation_short = inlines_or_nil(a["affiliation-short"]),
      presenter = a.presenter == true,
    }
    if author.presenter then
      if presenter then
        quarto.log.warning("program.lua: " .. where .. " has more than one `presenter: true`; using the first")
        author.presenter = false
      else
        presenter = author
      end
    end
    authors[#authors + 1] = author
  end
  -- No presenter marked: the first author presents.
  if not presenter and authors[1] then
    presenter = authors[1]
    presenter.presenter = true
  end

  -- Paper-style affiliations: each distinct affiliation gets a number (in
  -- order of first appearance), and each author points to theirs.
  local affiliations, affil_index = {}, {}
  for _, a in ipairs(authors) do
    if a.affiliation then
      local key = stringify(a.affiliation)
      if not affil_index[key] then
        affiliations[#affiliations + 1] = a.affiliation
        affil_index[key] = #affiliations
      end
      a.affil = affil_index[key]
    end
  end

  -- Abstract: the file body, minus comments. Empty -> placeholder.
  local abstract = doc.blocks:filter(function(b) return b.t ~= "RawBlock" end)
  if #abstract == 0 then
    abstract = pandoc.Blocks({ pandoc.Para({ pandoc.Emph(pandoc.Inlines("Abstract to come.")) }) })
  end

  local links = {}
  for _, l in ipairs(as_list(m.links)) do
    links[#links + 1] = { label = inlines_or_nil(l.label), url = stringify(l.url or "") }
  end

  -- `tbc: true` marks an unconfirmed talk: "(TBC)" follows its title everywhere.
  local title = inlines_or_nil(m.title)
  if title and m.tbc == true then
    title = title:clone()
    title:extend({ pandoc.Space(), pandoc.Str("(TBC)") })
  end

  return {
    file = where,
    folder = folder,
    id = "talk-" .. (file:gsub("%.md$", "")),
    order = tonumber(stringify(m.order or "")) or math.huge,
    title = title,
    authors = authors,
    presenter = presenter,
    affiliations = affiliations,
    links = links,
    abstract = abstract,
  }
end

-- Each subfolder of the talks folder is a session (e.g. talks/lightning-session-1/);
-- the folder a talk file sits in decides which session it belongs to.
local function load_talks(dir)
  local talks = {}
  local folders = sorted_listing(dir)
  if not folders then
    quarto.log.warning("program.lua: cannot read talks folder: " .. dir)
    return talks
  end

  for _, folder in ipairs(folders) do
    local files = not folder:match("^[_.]") and sorted_listing(pandoc.path.join({ dir, folder }))
    if files then
      for _, file in ipairs(files) do
        if file:match("%.md$") and not file:match("^_") then
          talks[#talks + 1] = load_talk(pandoc.path.join({ dir, folder, file }), folder, file)
        end
      end
    elseif folder:match("%.md$") and not folder:match("^_") then
      quarto.log.warning("program.lua: talks/" .. folder ..
        " is not in a session folder (e.g. talks/lightning-session-1/) and will not appear")
    end
  end

  -- Web link targets come from the file name ("talk-jane-smith"). When the
  -- same name is used in more than one session folder, add the folder so
  -- each talk's link stays unique ("talk-jane-smith-panel-session").
  local seen = {}
  for _, t in ipairs(talks) do seen[t.id] = (seen[t.id] or 0) + 1 end
  for _, t in ipairs(talks) do
    if seen[t.id] > 1 then t.id = t.id .. "-" .. t.folder end
  end

  -- Sort by `order`, then file name.
  table.sort(talks, function(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.file < b.file
  end)
  return talks
end

local function talks_in(talks, folder)
  local out = {}
  for _, t in ipairs(talks) do
    if t.folder == folder then out[#out + 1] = t end
  end
  return out
end

local function load_program(meta)
  local dir = stringify(meta["talks-dir"] or "talks")
  if not pandoc.path.is_absolute(dir) then
    local base = quarto.project.directory or pandoc.path.directory(quarto.doc.input_file)
    dir = pandoc.path.join({ base, dir })
  end
  local talks = load_talks(dir)

  local ev = meta.event or {}
  local event = { logos = {} }
  for _, key in ipairs({ "kicker", "title", "byline", "date", "time", "venue", "note", "support" }) do
    event[key] = inlines_or_nil(ev[key])
  end
  -- Each logo is a path, or { file = path, alt = description }.
  for _, l in ipairs(as_list(ev.logos)) do
    if type(l) == "table" and l.file then
      event.logos[#event.logos + 1] = { file = stringify(l.file), alt = stringify(l.alt or "") }
    else
      event.logos[#event.logos + 1] = { file = stringify(l), alt = "" }
    end
  end
  event.logos_label = inlines_or_nil(ev["logos-label"])

  local sessions = {}
  for _, s in ipairs(as_list(meta.sessions)) do
    sessions[#sessions + 1] = {
      time = inlines_or_nil(s.time),
      title = inlines_or_nil(s.title),
      description = inlines_or_nil(s.description),
      kind = s.kind and stringify(s.kind) or "session",
      talks = s.talks and talks_in(talks, stringify(s.talks)) or {},
    }
  end

  local groups, known = {}, {}
  for _, tf in ipairs(as_list(meta["talk-folders"])) do
    local folder = stringify(tf.folder)
    known[folder] = true
    groups[#groups + 1] = {
      folder = folder,
      label = inlines_or_nil(tf.label) or pandoc.Inlines(folder),
      talks = talks_in(talks, folder),
      new_page = tf["new-page"] == true,
    }
  end
  for _, t in ipairs(talks) do
    if not known[t.folder] then
      quarto.log.warning("program.lua: " .. t.file .. " is in folder '" .. t.folder ..
        "', which is not listed under talk-folders in schedule.yml")
    end
  end

  return { event = event, sessions = sessions, groups = groups, draft = inlines_or_nil(meta["draft-notice"]) }
end

-- Display URL: drop the scheme and any trailing slash.
local function short_url(url)
  return (url:gsub("^https?://", ""):gsub("/$", ""))
end

-- PDF writer (Typst) -----------------------------------------------------

local T = {}

function T.str(s)
  s = s:gsub("\\", "\\\\"):gsub('"', '\\"')
  return '"' .. s .. '"'
end

-- Blocks -> Typst content block: [ ... ]
function T.content(blocks)
  local out = pandoc.write(pandoc.Pandoc(blocks), "typst")
  out = out:gsub("^%s+", ""):gsub("%s+$", "")
  return "[" .. out .. "]"
end

-- Inlines (or nil) -> Typst content, or `none`.
function T.inl(inl)
  if inl == nil then return "none" end
  return T.content({ pandoc.Plain(inl) })
end

function T.array(items)
  if #items == 0 then return "()" end
  return "(" .. table.concat(items, ", ") .. ",)"
end

-- pairs_list is an ordered list of { key, typst_value }
function T.dict(pairs_list)
  local parts = {}
  for _, kv in ipairs(pairs_list) do parts[#parts + 1] = kv[1] .. ": " .. kv[2] end
  return "(" .. table.concat(parts, ", ") .. ")"
end

function T.authors(authors)
  local out = {}
  for _, a in ipairs(authors) do
    out[#out + 1] = T.dict({
      { "name", T.inl(a.name) },
      { "honorific", T.inl(a.honorific) },
      { "affiliation", T.inl(a.affiliation) },
      { "affiliation-short", T.inl(a.affiliation_short) },
      { "presenter", a.presenter and "true" or "false" },
      { "affil", a.affil and tostring(a.affil) or "none" },
    })
  end
  return T.array(out)
end

function T.header(event, draft)
  local args = {}
  for _, key in ipairs({ "kicker", "title", "byline", "date", "time", "venue", "note", "support" }) do
    args[#args + 1] = key .. ": " .. T.inl(event[key])
  end
  local logos = {}
  for _, l in ipairs(event.logos) do
    logos[#logos + 1] = "image(" .. T.str(l.file) .. ", height: 100%, alt: " .. T.str(l.alt) .. ")"
  end
  args[#args + 1] = "logos-label: " .. T.inl(event.logos_label)
  args[#args + 1] = "logos: " .. T.array(logos)
  args[#args + 1] = "draft: " .. T.inl(draft)
  return pandoc.RawBlock("typst", "#event-header(" .. table.concat(args, ",\n  ") .. ")")
end

function T.schedule(sessions)
  local rows = {}
  for _, s in ipairs(sessions) do
    local items = {}
    for _, t in ipairs(s.talks) do
      items[#items + 1] = T.dict({ { "title", T.inl(t.title) }, { "speakers", T.authors({ t.presenter }) } })
    end
    rows[#rows + 1] = T.dict({
      { "time", T.inl(s.time) },
      { "title", T.inl(s.title) },
      { "description", T.inl(s.description) },
      { "kind", T.str(s.kind) },
      { "talks", T.array(items) },
    })
  end
  return pandoc.RawBlock("typst", "#schedule-table(" .. T.array(rows) .. ")")
end

function T.talks(groups)
  local blocks = pandoc.Blocks({})
  for _, g in ipairs(groups) do
    if #g.talks > 0 then
      local entries = {}
      for _, t in ipairs(g.talks) do
        local links = {}
        for _, l in ipairs(t.links) do
          links[#links + 1] = T.dict({ { "label", T.inl(l.label) }, { "url", T.str(l.url) } })
        end
        entries[#entries + 1] = "#talk-entry(" .. table.concat({
          "title: " .. T.inl(t.title),
          "authors: " .. T.authors(t.authors),
          "affiliations: " .. T.array((function()
            local out = {}
            for _, aff in ipairs(t.affiliations) do out[#out + 1] = T.inl(aff) end
            return out
          end)()),
          "links: " .. T.array(links),
          "abstract: " .. (#t.abstract > 0 and T.content(t.abstract) or "none"),
        }, ",\n  ") .. ")"
      end
      -- `weak: true` skips the break if the session already starts a page.
      if g.new_page then
        blocks:insert(pandoc.RawBlock("typst", "#pagebreak(weak: true)"))
      end
      -- Written as raw Typst: Quarto shifts pandoc heading levels for PDFs.
      blocks:insert(pandoc.RawBlock("typst", "#heading(level: 1)" .. T.inl(g.label) .. " <talks-" .. g.folder .. ">"))
      blocks:insert(pandoc.RawBlock("typst", table.concat(entries, "\n\n")))
    end
  end
  return blocks
end

function T.todo(div)
  return pandoc.RawBlock("typst", "#todo-box(" .. T.content(div.content) .. ")")
end

-- Web writer (HTML) ------------------------------------------------------
-- Class names are styled in theme/web.scss.

local H = {}

function H.attr(s)
  return (s:gsub("&", "&amp;"):gsub('"', "&quot;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function H.inl(inl)
  if inl == nil then return "" end
  return (pandoc.write(pandoc.Pandoc({ pandoc.Plain(inl) }), "html"):gsub("%s+$", ""))
end

function H.blocks(blocks)
  return pandoc.write(pandoc.Pandoc(blocks), "html")
end

function H.tag(name, class, inner)
  return "<" .. name .. ' class="' .. class .. '">' .. inner .. "</" .. name .. ">"
end

-- "Name (Short affiliation)" list for the schedule: a, b & c
function H.speakers_short(speakers)
  local parts = {}
  for _, sp in ipairs(speakers) do
    local aff = sp.affiliation_short or sp.affiliation
    parts[#parts + 1] = H.inl(sp.name) .. (aff and (" (" .. H.inl(aff) .. ")") or "")
  end
  if #parts <= 1 then return parts[1] or "" end
  return table.concat(parts, ", ", 1, #parts - 1) .. " &amp; " .. parts[#parts]
end

function H.draft_banner(draft)
  return pandoc.RawBlock("html", '<div class="draft-banner" role="note">' .. H.inl(draft) .. "</div>")
end

function H.header(event)
  local out = { '<header class="event-header">' }
  if event.kicker then out[#out + 1] = H.tag("p", "event-header__kicker", H.inl(event.kicker)) end
  if event.title then out[#out + 1] = H.tag("h1", "event-header__title", H.inl(event.title)) end
  if event.byline then out[#out + 1] = H.tag("p", "event-header__byline", H.inl(event.byline)) end
  if event.date then out[#out + 1] = H.tag("p", "event-header__date", H.inl(event.date)) end
  if event.time then out[#out + 1] = H.tag("p", "event-header__time", H.inl(event.time)) end
  local place = {}
  if event.venue then place[#place + 1] = H.inl(event.venue) end
  if event.note then place[#place + 1] = H.inl(event.note) end
  if #place > 0 then out[#out + 1] = H.tag("p", "event-header__place", table.concat(place, " · ")) end
  if event.support then out[#out + 1] = H.tag("p", "event-header__place", H.inl(event.support)) end
  if #event.logos > 0 then
    if event.logos_label then out[#out + 1] = H.tag("p", "event-header__place", H.inl(event.logos_label)) end
    local imgs = {}
    for _, l in ipairs(event.logos) do
      imgs[#imgs + 1] = '<img src="' .. H.attr(l.file) .. '" alt="' .. H.attr(l.alt) .. '">'
    end
    out[#out + 1] = H.tag("div", "event-header__logos", table.concat(imgs))
  end
  out[#out + 1] = "</header>"
  return pandoc.RawBlock("html", table.concat(out, "\n"))
end

-- talks_page: page holding the talk details ("" = this page).
function H.schedule(sessions, talks_page)
  talks_page = talks_page or ""
  local out = { '<section class="schedule" aria-label="Schedule">' }
  for _, s in ipairs(sessions) do
    local body = { H.tag("h3", "session__title", H.inl(s.title)) }
    if s.description then body[#body + 1] = H.tag("p", "session__description", H.inl(s.description)) end
    if #s.talks > 0 then
      local items = {}
      for _, t in ipairs(s.talks) do
        items[#items + 1] = '<li><a class="talk-link" href="' .. H.attr(talks_page) .. '#' .. t.id .. '">' .. H.inl(t.title) .. "</a>" ..
          H.tag("span", "talk-link__speakers", H.speakers_short({ t.presenter })) .. "</li>"
      end
      local class = "session__talks" .. (#s.talks > TWO_COLUMNS_AFTER and " session__talks--columns" or "")
      body[#body + 1] = H.tag("ul", class, table.concat(items))
    end
    out[#out + 1] = H.tag("div", "session session--" .. H.attr(s.kind),
      H.tag("div", "session__time", H.inl(s.time)) ..
      H.tag("div", "session__body", table.concat(body)))
  end
  out[#out + 1] = "</section>"
  return pandoc.RawBlock("html", table.concat(out, "\n"))
end

function H.talks(groups)
  local blocks = pandoc.Blocks({})

  -- "Jump to" links between sessions (the side contents list is hidden on
  -- small screens, so web.scss shows this there instead).
  local jumps = {}
  for _, g in ipairs(groups) do
    if #g.talks > 0 then
      jumps[#jumps + 1] = '<a href="#talks-' .. H.attr(g.folder) .. '">' .. H.inl(g.label) .. "</a>"
    end
  end
  if #jumps > 1 then
    blocks:insert(pandoc.RawBlock("html", '<nav class="talks-jump" aria-label="Sessions">Jump to: ' ..
      table.concat(jumps, " · ") .. "</nav>"))
  end

  for _, g in ipairs(groups) do
    if #g.talks > 0 then
      blocks:insert(pandoc.Header(2, g.label, pandoc.Attr("talks-" .. g.folder)))
      local articles = {}
      for _, t in ipairs(g.talks) do
        -- Paper style: names on one line (presenter in bold), then the
        -- affiliations, numbered with superscripts when there's more than one.
        -- Honorifics are shown for single authors only.
        local numbered = #t.affiliations > 1
        local honorifics = #t.authors == 1
        local authors = {}
        for _, a in ipairs(t.authors) do
          local name = ((honorifics and a.honorific) and (H.inl(a.honorific) .. " ") or "") .. H.inl(a.name)
          authors[#authors + 1] = '<span class="author' .. (a.presenter and " author--presenter" or "") .. '">' ..
            name .. ((numbered and a.affil) and ("<sup>" .. a.affil .. "</sup>") or "") .. "</span>"
        end
        local affils = {}
        for i, aff in ipairs(t.affiliations) do
          affils[#affils + 1] = "<span>" .. (numbered and ("<sup>" .. i .. "</sup>") or "") .. H.inl(aff) .. "</span>"
        end
        local parts = {
          '<article class="talk" id="' .. t.id .. '">',
          H.tag("h3", "talk__title", H.inl(t.title)),
          H.tag("p", "talk__authors", table.concat(authors, ", ")),
          #affils > 0 and H.tag("p", "talk__affiliations", table.concat(affils, " ")) or "",
          H.tag("div", "talk__abstract", H.blocks(t.abstract)),
        }
        if #t.links > 0 then
          local items = {}
          for _, l in ipairs(t.links) do
            items[#items + 1] = "<li>" ..
              (l.label and (H.tag("span", "talk__link-label", H.inl(l.label)) .. ": ") or "") ..
              '<a href="' .. H.attr(l.url) .. '">' .. H.attr(short_url(l.url)) .. "</a></li>"
          end
          parts[#parts + 1] = H.tag("ul", "talk__links", table.concat(items))
        end
        parts[#parts + 1] = "</article>"
        articles[#articles + 1] = table.concat(parts, "\n")
      end
      blocks:insert(pandoc.RawBlock("html", table.concat(articles, "\n")))
    end
  end
  return blocks
end

-- Main -------------------------------------------------------------------

function Pandoc(doc)
  local W
  if quarto.doc.is_format("typst") then
    W = T
  elseif quarto.doc.is_format("html") then
    W = H
  else
    return nil
  end

  local program = load_program(doc.meta)

  doc.blocks = doc.blocks:walk({
    Div = function(div)
      if div.classes:includes("program-header") then
        return W.header(program.event, program.draft)
      elseif div.classes:includes("program-schedule") then
        local schedule = W.schedule(program.sessions, div.attributes["talks-page"])
        if div.attributes.header == "false" then return schedule end
        return pandoc.Blocks({ W.header(program.event, program.draft), schedule })
      elseif div.classes:includes("program-talks") then
        return W.talks(program.groups)
      elseif div.classes:includes("todo") and W.todo then
        return W.todo(div)
      end
    end,
  })

  -- Web: draft banner at the top of every page.
  if W == H and program.draft then doc.blocks:insert(1, H.draft_banner(program.draft)) end
  return doc
end
