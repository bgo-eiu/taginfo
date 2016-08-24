# web/lib/api/v4/key.rb
class Taginfo < Sinatra::Base

    api(4, 'key/combinations', {
        :description => 'Find keys that are used together with a given key.',
        :parameters => {
            :key => 'Tag key (required).',
            :query => 'Only show results where the other_key matches this query (substring match, optional).'
        },
        :paging => :optional,
        :filter => {
            :all       => { :doc => 'No filter.' },
            :nodes     => { :doc => 'Only values on tags used on nodes.' },
            :ways      => { :doc => 'Only values on tags used on ways.' },
            :relations => { :doc => 'Only values on tags used on relations.' }
        },
        :sort => %w( together_count other_key from_fraction ),
        :result => paging_results([
            [:other_key,      :STRING, 'Other key.'],
            [:together_count, :INT,    'Number of objects that have both keys.'],
            [:to_fraction,    :FLOAT,  'Fraction of objects with this key that also have the other key.'],
            [:from_fraction,  :FLOAT,  'Fraction of objects with other key that also have this key.']
        ]),
        :example => { :key => 'highway', :page => 1, :rp => 10, :sortname => 'together_count', :sortorder => 'desc' },
        :ui => '/keys/highway#combinations'
    }) do
        key = params[:key]
        filter_type = get_filter()

        if @ap.sortname == 'to_count'
            @ap.sortname = ['together_count']
        elsif @ap.sortname == 'from_count'
            @ap.sortname = ['from_fraction', 'together_count', 'other_key']
        end

        cq = @db.count('db.key_combinations')
        total = (params[:query].to_s != '' ?
                    cq.condition("(key1=? AND key2 LIKE ? ESCAPE '@') OR (key2=? AND key1 LIKE ? ESCAPE '@')", key, like_contains(params[:query]), key, like_contains(params[:query])) :
                    cq.condition('key1 = ? OR key2 = ?', key, key)
                ).
            condition_if_true("count_#{filter_type} > 0", filter_type != 'all').
            get_first_i

        has_this_key = @db.select("SELECT count_#{filter_type} FROM db.keys").
            condition('key = ?', key).
            get_first_value()

        res = (params[:query].to_s != '' ?
            @db.select("SELECT p.key1 AS other_key, p.count_#{filter_type} AS together_count, k.count_#{filter_type} AS other_count, CAST(p.count_#{filter_type} AS REAL) / k.count_#{filter_type} AS from_fraction FROM db.key_combinations p, db.keys k WHERE p.key1=k.key AND p.key2=? AND (p.key1 LIKE ? ESCAPE '@') AND p.count_#{filter_type} > 0
                    UNION SELECT p.key2 AS other_key, p.count_#{filter_type} AS together_count, k.count_#{filter_type} AS other_count, CAST(p.count_#{filter_type} AS REAL) / k.count_#{filter_type} AS from_fraction FROM db.key_combinations p, db.keys k WHERE p.key2=k.key AND p.key1=? AND (p.key2 LIKE ? ESCAPE '@') AND p.count_#{filter_type} > 0", key, like_contains(params[:query]), key, like_contains(params[:query])) :
            @db.select("SELECT p.key1 AS other_key, p.count_#{filter_type} AS together_count, k.count_#{filter_type} AS other_count, CAST(p.count_#{filter_type} AS REAL) / k.count_#{filter_type} AS from_fraction FROM db.key_combinations p, db.keys k WHERE p.key1=k.key AND p.key2=? AND p.count_#{filter_type} > 0
                    UNION SELECT p.key2 AS other_key, p.count_#{filter_type} AS together_count, k.count_#{filter_type} AS other_count, CAST(p.count_#{filter_type} AS REAL) / k.count_#{filter_type} AS from_fraction FROM db.key_combinations p, db.keys k WHERE p.key2=k.key AND p.key1=? AND p.count_#{filter_type} > 0", key, key)).
            order_by(@ap.sortname, @ap.sortorder) { |o|
                o.together_count
                o.other_key
                o.from_fraction
            }.
            paging(@ap).
            execute()

        return generate_json_result(total,
            res.map{ |row| {
                :other_key      => row['other_key'],
                :together_count => row['together_count'].to_i,
                :to_fraction    => (row['together_count'].to_f / has_this_key.to_f).round(4),
                :from_fraction  => row['from_fraction'].to_f.round(4)
            } }
        )
    end

    api(4, 'key/similar', {
        :description => 'Find keys that are similar to a given key.',
        :parameters => {
            :key => 'Tag key (required).',
            :query => 'Only show results where the other_key matches this query (substring match, optional).'
        },
        :paging => :optional,
        :sort => %w( other_key count_all similarity ),
        :result => paging_results([
            [:other_key,  :STRING, 'Other key.'],
            [:count_all,  :INT,    'Number of objects that have the other key.'],
            [:similarity, :INT,    'An integer measuring the similarity of the two keys, smaller is more similar.']
        ]),
        :example => { :key => 'highway', :page => 1, :rp => 10, :sortname => 'other_key', :sortorder => 'asc' },
        :ui => '/keys/highway#similar'
    }) do
        key = params[:key]
        query = like_contains(params[:query])

        if params[:query].to_s != ''
            total = @db.select("SELECT count(*) FROM db.similar_keys s WHERE (s.key1 LIKE ? ESCAPE '@') AND s.key2=?
                                                                          OR (s.key2 LIKE ? ESCAPE '@') AND s.key1=?", query, key, query, key).get_first_i
        else
            total = @db.count('db.similar_keys').
                        condition("key1=? OR key2=?", key, key).
                        get_first_i
        end

        rows = (params[:query].to_s != '' ?
            @db.select("SELECT key1 AS other_key, count_all1 AS count_all, similarity FROM db.similar_keys WHERE (key1 LIKE ? ESCAPE '@') AND key2=?
                  UNION SELECT key2 AS other_key, count_all2 AS count_all, similarity FROM db.similar_keys WHERE (key2 LIKE ? ESCAPE '@') AND key1=?", query, key, query, key) :
            @db.select("SELECT key1 AS other_key, count_all1 AS count_all, similarity FROM db.similar_keys WHERE key2=?
                  UNION SELECT key2 AS other_key, count_all2 AS count_all, similarity FROM db.similar_keys WHERE key1=?", key, key)).
                    order_by(@ap.sortname, @ap.sortorder) { |o|
                        o.similarity :similarity
                        o.similarity :count_all
                        o.other_key
                        o.count_all :count_all
                        o.count_all :similarity
                    }.
                    paging(@ap).
                    execute()

        return generate_json_result(total,
            rows.map{ |row| {
                :other_key  => row['other_key'],
                :count_all  => row['count_all'],
                :similarity => row['similarity']
            } }
        )
    end

    api(4, 'key/distribution/nodes', {
        :description => 'Get map with distribution of this key in the database (nodes only).',
        :parameters => { :key => 'Tag key (required).' },
        :result => 'PNG image.',
        :example => { :key => 'amenity' },
        :ui => '/keys/amenity#map'
    }) do
        get_png('key', 'n', params[:key])
    end

    api(4, 'key/distribution/ways', {
        :description => 'Get map with distribution of this key in the database (ways only).',
        :parameters => { :key => 'Tag key (required).' },
        :result => 'PNG image.',
        :example => { :key => 'highway' },
        :ui => '/keys/highway#map'
    }) do
        get_png('key', 'w', params[:key])
    end

    api(4, 'key/stats', {
        :description => 'Show some database statistics for given key.',
        :parameters => { :key => 'Tag key (required).' },
        :result => no_paging_results([
            [:type,           :STRING, 'Object type ("all", "nodes", "ways", or "relations")'],
            [:count,          :INT,    'Number of objects with this type and key.'],
            [:count_fraction, :FLOAT,  'Number of objects in relation to all objects.'],
            [:values,         :INT,    'Number of different values for this key.']
        ]),
        :example => { :key => 'amenity' },
        :ui => '/keys/amenity#overview'
    }) do
        key = params[:key]
        out = []

        # default values
        ['all', 'nodes', 'ways', 'relations'].each_with_index do |type, n|
            out[n] = { :type => type, :count => 0, :count_fraction => 0.0, :values => 0 }
        end

        @db.select('SELECT * FROM db.keys').
            condition('key = ?', key).
            execute() do |row|
                ['all', 'nodes', 'ways', 'relations'].each_with_index do |type, n|
                    out[n] = {
                        :type           => type,
                        :count          => row['count_'  + type].to_i,
                        :count_fraction => (row['count_'  + type].to_f / get_total(type)).round(4),
                        :values         => row['values_' + type].to_i
                    }
                end
            end

        return generate_json_result(4, out);
    end

    api(4, 'key/values', {
        :description => 'Get values used with a given key.',
        :parameters => {
            :key => 'Tag key (required).',
            :lang => "Language for description (optional, default: 'en').",
            :query => 'Only show results where the value matches this query (substring match, optional).'
        },
        :paging => :optional,
        :filter => {
            :all       => { :doc => 'No filter.' },
            :nodes     => { :doc => 'Only values on tags used on nodes.' },
            :ways      => { :doc => 'Only values on tags used on ways.' },
            :relations => { :doc => 'Only values on tags used on relations.' }
        },
        :sort => %w( value count_all count_nodes count_ways count_relations in_wiki ),
        :result => paging_results([
            [:value,       :STRING, 'Value'],
            [:count,       :INT,    'Number of times this key/value is in the OSM database.'],
            [:fraction,    :FLOAT,  'Number of times in relation to number of times this key is in the OSM database.'],
            [:in_wiki,     :BOOL,   'Is there at least one wiki page for this tag.'],
            [:description, :STRING, 'Description of the tag from the wiki.']
        ]),
        :example => { :key => 'highway', :page => 1, :rp => 10, :sortname => 'count_ways', :sortorder => 'desc' },
        :ui => '/keys/highway#values'
    }) do
        key = params[:key]
        lang = params[:lang] || 'en'
        filter_type = get_filter()

        if @ap.sortname == 'count'
            @ap.sortname = ['count_' + filter_type]
        end

        (this_key_count, total) = @db.select("SELECT count_#{filter_type} AS count, values_#{filter_type} AS count_values FROM db.keys").
            condition('key = ?', key).
            get_columns(:count, :count_values)

        if params[:query].to_s != ''
            total = @db.count('db.tags').
                condition('key = ?', key).
                condition_if_true("count_#{filter_type} > 0", filter_type != 'all').
                condition_if("value LIKE ? ESCAPE '@'", like_contains(params[:query])).
                get_first_value()
        end

        res = @db.select('SELECT * FROM db.tags').
            condition('key = ?', key).
            condition_if_true("count_#{filter_type} > 0", filter_type != 'all').
            condition_if("value LIKE ? ESCAPE '@'", like_contains(params[:query])).
            order_by(@ap.sortname, @ap.sortorder) { |o|
                o.value
                o.count_all
                o.count_nodes
                o.count_ways
                o.count_relations
                o.in_wiki :in_wiki
                o.in_wiki! :value
            }.
            paging(@ap).
            execute()

        values_with_wiki_page = res.select{ |row| row['in_wiki'].to_i != 0 }.map{ |row| "'" + SQLite3::Database.quote(row['value']) + "'" }.join(',')

        # Read description for tag from wikipages, first in English then in the chosen
        # language. This way the chosen language description will overwrite the default
        # English one.
        wikidesc = {}

        if values_with_wiki_page != ''
            ['en', lang].uniq.each do |lang|
                @db.select('SELECT value, description FROM wiki.wikipages').
                    condition('lang = ?', lang).
                    condition('key = ?', key).
                    condition("value IN (#{ values_with_wiki_page })").
                    execute().each do |row|
                    wikidesc[row['value']] = row['description']
                end
            end
        end

        return generate_json_result(total,
            res.map{ |row| {
                :value    => row['value'],
                :count    => row['count_' + filter_type].to_i,
                :fraction => (row['count_' + filter_type].to_f / this_key_count.to_f).round(4),
                :in_wiki  => row['in_wiki'] != 0,
                :description => wikidesc[row['value']] || ''
            } }
        )
    end

    api(4, 'key/wiki_pages', {
        :description => 'Get list of wiki pages in different languages describing a key.',
        :parameters => { :key => 'Tag key (required)' },
        :paging => :no,
        :result => no_paging_results([
            [:lang,             :STRING, 'Language code.'],
            [:language,         :STRING, 'Language name in its language.'],
            [:language_en,      :STRING, 'Language name in English.'],
            [:title,            :STRING, 'Wiki page title.'],
            [:description,      :STRING, 'Short description of key from wiki page.'],
            [:image,            :HASH,   'Associated image.', [
                [:title,            :STRING, 'Wiki page title of associated image.' ],
                [:width,            :INT,    'Width of image.' ],
                [:height,           :INT,    'Height of image.' ],
                [:mime,             :STRING, 'MIME type of image.' ],
                [:image_url,        :STRING, 'Image URL' ],
                [:thumb_url_prefix, :STRING, 'Prefix of thumbnail URL.' ],
                [:thumb_url_suffix, :STRING, 'Suffix of thumbnail URL.' ]
            ]],
            [:on_node,          :BOOL,   'Is this a key for nodes?'],
            [:on_way,           :BOOL,   'Is this a key for ways?'],
            [:on_area,          :BOOL,   'Is this a key for areas?'],
            [:on_relation,      :BOOL,   'Is this a key for relations?'],
            [:tags_implies,     :ARRAY_OF_STRINGS, 'List of keys/tags implied by this key.'],
            [:tags_combination, :ARRAY_OF_STRINGS, 'List of keys/tags that can be combined with this key.'],
            [:tags_linked,      :ARRAY_OF_STRINGS, 'List of keys/tags related to this key.']
        ]),
        :notes => 'To get the complete thumbnail image URL, concatenate <tt>thumb_url_prefix</tt>, width of image in pixels, and <tt>thumb_url_suffix</tt>. The thumbnail image width must be smaller than <tt>width</tt>, use the <tt>image_url</tt> otherwise.',
        :example => { :key => 'highway' },
        :ui => '/keys/highway#wiki'
    }) do
        key = params[:key]

        res = @db.execute('SELECT * FROM wikipages LEFT OUTER JOIN wiki_images USING (image) WHERE value IS NULL AND key = ? ORDER BY lang', key)

        return get_wiki_result(res)
    end

    api(4, 'key/projects', {
        :description => 'Get projects using a given key.',
        :parameters => {
            :key => 'Tag key (required).',
            :query => 'Only show results where the project name or tag value matches this query (substring match, optional).'
        },
        :paging => :optional,
        :filter => {
            :all       => { :doc => 'No filter.' },
            :nodes     => { :doc => 'Only values on tags used on nodes.' },
            :ways      => { :doc => 'Only values on tags used on ways.' },
            :relations => { :doc => 'Only values on tags used on relations.' }
        },
        :sort => %w( project_name tag ),
        :result => paging_results([
            [:project_id,       :STRING, 'Project ID'],
            [:project_name,     :STRING, 'Project name'],
            [:project_icon_url, :STRING, 'Project icon URL'],
            [:key,              :STRING, 'Key'],
            [:value,            :STRING, 'Value'],
            [:on_node,          :BOOL,   'For nodes?'],
            [:on_way,           :BOOL,   'For ways?'],
            [:on_relation,      :BOOL,   'For relations?'],
            [:on_area,          :BOOL,   'For areas?'],
            [:description,      :STRING, 'Description'],
            [:doc_url,          :STRING, 'Documentation URL'],
            [:icon_url,         :STRING, 'Icon URL']
        ]),
        :example => { :key => 'highway', :page => 1, :rp => 10, :sortname => 'project_name', :sortorder => 'asc' },
        :ui => '/keys/highway=residential#projects'
    }) do
        key = params[:key]
        q = like_contains(params[:query])
        filter_type = get_filter()

        total = @db.select('SELECT count(*) FROM projects.projects p, projects.project_tags t ON p.id=t.project_id').
            condition("status = 'OK'").
            condition('key = ?', key).
            condition_if("value LIKE ? ESCAPE '@' OR name LIKE ? ESCAPE '@'", q, q).
            condition_if("on_node = ?",                    filter_type == 'nodes'     ? 1 : '').
            condition_if("on_way = ? OR on_area = 1",      filter_type == 'ways'      ? 1 : '').
            condition_if("on_relation = ? OR on_area = 1", filter_type == 'relations' ? 1 : '').
            get_first_i

        res = @db.select('SELECT t.project_id, p.name, p.icon_url AS project_icon_url, t.key, t.value, t.description, t.doc_url, t.icon_url, t.on_node, t.on_way, t.on_relation, t.on_area FROM projects.projects p, projects.project_tags t ON p.id=t.project_id').
            condition("status = 'OK'").
            condition('key = ?', key).
            condition_if("value LIKE ? ESCAPE '@' OR name LIKE ? ESCAPE '@'", q, q).
            condition_if("on_node = ?",                    filter_type == 'nodes'     ? 1 : '').
            condition_if("on_way = ? OR on_area = 1",      filter_type == 'ways'      ? 1 : '').
            condition_if("on_relation = ? OR on_area = 1", filter_type == 'relations' ? 1 : '').
            order_by(@ap.sortname, @ap.sortorder) { |o|
                o.project_name 'lower(p.name)'
                o.project_name :value
                o.tag :value
                o.tag 'lower(p.name)'
            }.
            paging(@ap).
            execute()

        return generate_json_result(total,
            res.map{ |row| {
                :project_id       => row['project_id'],
                :project_name     => row['name'],
                :project_icon_url => row['project_icon_url'],
                :key              => row['key'],
                :value            => row['value'],
                :on_node          => row['on_node'].to_i     == 1,
                :on_way           => row['on_way'].to_i      == 1,
                :on_relation      => row['on_relation'].to_i == 1,
                :on_area          => row['on_area'].to_i     == 1,
                :description      => row['description'],
                :doc_url          => row['doc_url'],
                :icon_url         => row['icon_url']
            } }
        )
    end

end
