SUBSYSTEM_DEF(codex)
	name = "Codex"
	flags = SS_NO_FIRE
	init_order = INIT_ORDER_CODEX

	var/regex/linkRegex
	var/regex/trailingLinebreakRegexStart
	var/regex/trailingLinebreakRegexEnd

	var/list/all_entries = list()
	var/list/entries_by_path = list()
	var/list/entries_by_string = list()
	var/list/index_file = list()
	var/list/search_cache = list()
	var/list/codex_categories = list()

/datum/controller/subsystem/codex/Initialize()
	// Codex link syntax is such:
	// <l>keyword</l> when keyword is mentioned verbatim,
	// <span codexlink='keyword'>whatever</span> when shit gets tricky
	linkRegex = regex(@"<(span|l)(\s+codexlink='([^>]*)'|)>([^<]+)</(span|l)>","g")

	// Create general hardcoded entries.
	for(var/datum/codex_entry/entry as anything in subtypesof(/datum/codex_entry))
		if(initial(entry.name) && !(isabstract(entry)))
			entry = new entry()

	// Create categorized entries.
	var/list/deferred_population = list()
	for(var/path in subtypesof(/datum/codex_category))
		codex_categories[path] = new path

	for(var/ctype in codex_categories)
		var/datum/codex_category/cat = codex_categories[ctype]
		if(cat.defer_population)
			deferred_population += cat
			continue
		cat.Populate()

	for(var/datum/codex_category/cat as anything in deferred_population)
		cat.Populate()

	// Create the index file for later use.
	for(var/datum/codex_entry/entry as anything in all_entries)
		index_file[entry.name] = entry
	index_file = sortTim(index_file, GLOBAL_PROC_REF(cmp_text_asc))
	. = ..()

/datum/controller/subsystem/codex/proc/parse_links(string, viewer)
	while(linkRegex.Find(string))
		var/key = linkRegex.group[4]
		if(linkRegex.group[2])
			key = linkRegex.group[3]
		key = codex_sanitize(key)
		var/datum/codex_entry/linked_entry = get_entry_by_string(key)
		var/replacement = linkRegex.group[4]
		if(linked_entry)
			replacement = "<a href='?src=\ref[SScodex];show_examined_info=\ref[linked_entry];show_to=\ref[viewer]'>[replacement]</a>"
		string = replacetextEx(string, linkRegex.match, replacement)
	return string

/// Returns a codex entry for the given query. May return a list if multiple are found, or null if none.
/datum/controller/subsystem/codex/proc/get_codex_entry(entry)
	if(isatom(entry))
		var/atom/entity = entry
		. = entity.get_specific_codex_entry()
		if(.)
			return
		return entries_by_path[entity.type] || get_entry_by_string(entity.name)

	if(isdatum(entry))
		entry = entry:type
	if(ispath(entry))
		return entries_by_path[entry]
	if(istext(entry))
		return entries_by_string[codex_sanitize(entry)]

/datum/controller/subsystem/codex/proc/get_entry_by_string(string)
	return entries_by_string[codex_sanitize(string)]

/// Presents a codex entry to a mob. If it receives a list of entries, it will prompt them to choose one.
/datum/controller/subsystem/codex/proc/present_codex_entry(mob/presenting_to, datum/codex_entry/entry)
	if(!entry || !istype(presenting_to) || !presenting_to.client)
		return

	if(islist(entry))
		present_codex_search(presenting_to, entry)
		return

	var/datum/browser/popup = new(presenting_to, "codex", "Codex", nheight=425) //"codex\ref[entry]"
	var/entry_data = entry.get_codex_body(presenting_to)
	popup.set_content(parse_links(jointext(entry_data, null), presenting_to))
	popup.open()

#define CODEX_ENTRY_LIMIT 10
/// Presents a list of codex entries to a mob.
/datum/controller/subsystem/codex/proc/present_codex_search(mob/presenting_to, list/entries, search_query)
	var/list/codex_data = list()
	codex_data += "<h3><b>[all_entries.len] matches</b>[search_query ? "for '[search_query]'" : ""]:</h3>"

	if(LAZYLEN(entries) > CODEX_ENTRY_LIMIT)
		codex_data += "Showing first <b>[CODEX_ENTRY_LIMIT]</b> entries. <b>[all_entries.len - 5] result\s</b> omitted.</br>"
	codex_data += "<table width = 100%>"

	for(var/i = 1 to min(entries.len, CODEX_ENTRY_LIMIT))
		var/datum/codex_entry/entry = entries[i]
		codex_data += "<tr><td>[entry.name]</td><td><a href='?src=\ref[SScodex];show_examined_info=\ref[entry];show_to=\ref[presenting_to]'>View</a></td></tr>"
	codex_data += "</table>"

	var/datum/browser/popup = new(presenting_to, "codex-search", "Codex Search") //"codex-search"
	popup.set_content(codex_data.Join())
	popup.open()

#undef CODEX_ENTRY_LIMIT
/datum/controller/subsystem/codex/proc/get_guide(category)
	var/datum/codex_category/cat = codex_categories[category]
	. = cat?.guide_html

/datum/controller/subsystem/codex/proc/retrieve_entries_for_string(searching)

	if(!initialized)
		return list()

	searching = codex_sanitize(searching)

	if(!searching)
		return list()

	if(!search_cache[searching])
		var/list/results = list()
		if(entries_by_string[searching])
			results = entries_by_string[searching]
		else
			for(var/datum/codex_entry/entry as anything in all_entries)
				if(findtext(entry.name, searching) || findtext(entry.lore_text, searching) || findtext(entry.mechanics_text, searching) || findtext(entry.antag_text, searching))
					results += entry

		search_cache[searching] = sortTim(results, GLOBAL_PROC_REF(cmp_name_asc))
	return search_cache[searching]

/datum/controller/subsystem/codex/Topic(href, href_list)
	. = ..()
	if(!. && href_list["show_examined_info"] && href_list["show_to"])
		var/mob/showing_mob = locate(href_list["show_to"])
		if(!istype(showing_mob))
			return
		var/atom/showing_atom = locate(href_list["show_examined_info"])
		var/entry
		if(istype(showing_atom, /datum/codex_entry))
			entry = showing_atom
		else if(istype(showing_atom))
			entry = get_codex_entry(showing_atom.get_codex_value())
		else
			entry = get_codex_entry(href_list["show_examined_info"])

		if(entry)
			present_codex_entry(showing_mob, entry)
			return TRUE
