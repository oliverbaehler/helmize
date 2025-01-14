{{/* Train <Template> 

  Gathers all relevant files based on given paths, extensions and exclusions and returns the paths

  params <dict>: 
    files: <strict> Paths to look for files
    ctx: <dict> Global Context

  returns <dict>:
    files <slice>: contains all files
    errors <int>: amount of errors during file collection
    
*/}}
{{- define "helmize.core.func.train" -}}
  {{- if and $.files $.ctx -}}
    {{- $return := dict "wagons" list "paths" list "errors" list "debug" list -}}

    {{/* Variables */}}
    {{- $file_train := list -}}
    {{- $yaml_delimiter := "\n---" -}}
    {{- $order := 0 -}}
    
    {{/* Shared Data Over All Files */}}
    {{- $shared_data := dict -}}

    {{/* Paths */}}
    {{- $_ := set $return "paths" $.files -}}

    {{/* Iterate over files */}}
    {{- range $file := $.files -}}
      {{- $train_file := dict "files" (list $file) "errors" list "debug" list -}}

      {{/* Parse File */}}
      {{- $file_name := $file.file -}}

      {{/* Benchmark */}}
      {{- include "helmize.helpers.ts" (dict "msg" (printf "File %s initialied" $file_name) "ctx" $.ts) -}}

      {{/* Merge Data Store (Merges Condition Data with File Train Data Store */}}
      {{- $shared_data = mergeOverwrite $shared_data $file.data -}}

      {{/* Identifier for file */}}
      {{- $file_id := dict "file" $file_name "path" (dir $file.path) "filename" (base $file_name) -}}

      {{/* Get Content */}}
      {{- $content := ($.ctx.Files.Get $file_name) -}}

      {{/* Check if Content */}}
      {{- if $content -}}

        {{/* Initialize Context (Sets $.data and $.value key) */}}
        {{- $context := (set (set (set $.ctx "data" $shared_data) "value" (default dict $file.value)) "conditions" $.conditions) -}}

        {{/* Template File Content */}}
        {{- $template_content_raw := tpl $content $context -}}

        {{/* Split Content, We have to valuate YAML on each Splitted element */}}
        {{- $partial_files := splitList $yaml_delimiter $template_content_raw | compact -}}

        {{/* Iterate over Partial File */}}
        {{- range $partial_file_content := $partial_files -}}

          {{/* If not empty without Spaces */}}
          {{- if ($partial_file_content | nospace | trimAll "\n") -}}
          
            {{/* Parse Content as YAML */}}
            {{- $parsed_content := (fromYaml ($partial_file_content)) -}}

            {{/* Validate if parse was successful, otherwise return with error */}}
            {{- if not (include "lib.utils.errors.unmarshalingError" $parsed_content) -}}
  
              {{/* Variables */}}
              {{- $matched := 0 -}}
              {{- $match_count := 0 -}}
              {{- $fork := 0 -}}
  
              {{/* File Struct */}}
              {{- $incoming_wagon := dict "id" list "content" $parsed_content "file_id" $file_id "subpath" (regexReplaceAll $file_id.path $file_id.file "${1}" | trimPrefix "/" | dir) "renderers" $file.renderers "debug" list "errors" list -}}
  
              {{/* Benchmark */}}
              {{- include "helmize.helpers.ts" (dict "msg" (printf "Evaluating Configuration") "ctx" $.ts) -}}

              {{/* Resolve File Configuration within file, if not set get empty dict */}}
              {{- $file_cfg_path := (fromYaml (include "helmize.config.func.resolve" (dict "path" (include "helmize.config.defaults.file_cfg_key" $) "ctx" $.ctx))).res -}}
              {{- $file_cfg := mergeOverwrite (get $file "config") (default dict (fromYaml (include "lib.utils.dicts.get" (dict "data" $incoming_wagon.content "path" $file_cfg_path))).res) -}}
      
              {{/* Compares against Type, Defaults are already set via conditions */}}
              {{- $file_cfg_type := fromYaml (include "lib.utils.types.validate" (dict "type" "helmize.core.types.file_configuration"  "data" $file_cfg "ctx" $.ctx)) -}}
              {{- if $file_cfg_type.isType -}}

                {{/* Set Configuration */}}
                {{- $_ := set $incoming_wagon "config" $file_cfg -}}

                {{/* Redirect Render config */}}
                {{- $_ := set $incoming_wagon "render" (get $file_cfg (include "helmize.core.defaults.file_cfg.render" $)) -}}

              {{- else -}}
                {{/* Error Redirect */}}
                {{- $_ := set $incoming_wagon "errors" (append $incoming_wagon.errors (dict "error" "File has type errors" "type_errors" $file_cfg_type.errors)) -}}
              {{- end -}}
  
              {{/* Benchmark */}}
              {{- include "helmize.helpers.ts" (dict "msg" (printf "Running Identifier") "ctx" $.ts) -}}
    
              {{/* Evaluate Identifier */}}
              {{- include "helmize.core.func.identifier" (dict "wagon" $incoming_wagon "ctx" $context) -}}
                 
              {{/* Benchmark */}}
              {{- include "helmize.helpers.ts" (dict "msg" (printf "Got Identifier") "ctx" $.ts) -}}

              {{/* Unset Configuration In Content */}}
              {{- include "lib.utils.dicts.unset"  (dict "data" $incoming_wagon.content "path" $file_cfg_path) -}}

              {{/* Handle Errors (File Won't be merged) */}}
              {{- if $incoming_wagon.errors -}}
                {{- $_ := set $return "errors" (append $return.errors (dict "file" $file_name "errors" $incoming_wagon.errors)) -}}
              {{- else -}}
  
                {{/* Always Add File */}}
                {{- $_ := set $incoming_wagon "files" (list (omit (set (set (set $file "_order" $order) "config" $file_cfg) "ids" $incoming_wagon.id) "partial_files")) -}}

                {{/* Further Debug */}}
                {{- if (include "helmize.render.func.debug" $.ctx) -}}
                  {{- $_ := set $return "debug" (append $return.debug (dict "Source" $file.file "Manifest" $incoming_wagon)) -}}
                {{- end -}}
  
                {{/* Iterate Trough Train to find Matches */}}
                {{- range $i, $wagon := $file_train -}}
    
                  {{/* Validate Subpath */}}
                  {{- if (or (not (get $file_cfg (include "helmize.core.defaults.file_cfg.subpath" $))) (and (get $file_cfg (include "helmize.core.defaults.file_cfg.subpath" $)) (eq $incoming_wagon.subpath $wagon.subpath))) -}}
    
                    {{/* ForEach incomfing ID iterate */}}
                    {{- range $id := $incoming_wagon.id -}}
                        
                      {{/* Check Against existing Wagon IDs */}}
                      {{- range $wagon_id := $wagon.id -}}

                        {{/* Check if already forked */}}
                        {{- if (not $fork) -}}

                          {{/* Validate Match Counter */}}
                          {{- if (le ((default 0 (get $file_cfg (include "helmize.core.defaults.file_cfg.max_match" $))) | int) ($match_count | int)) -}}
        
                            {{/* Check Match */}}
                            {{- if (or (eq $id $wagon_id) (and (get $file_cfg (include "helmize.core.defaults.file_cfg.pattern" $)) (regexFind $id $wagon_id))) -}}
            
                              {{/* Fork to new File */}}
                              {{- if (get $file_cfg (include "helmize.core.defaults.file_cfg.fork" $)) -}}
    
                                {{/* Create new reference */}}
                                {{- $fork = toYaml $incoming_wagon -}}
                                {{- $fork = fromYaml ($fork) -}}
    
                                {{/* Files to new Fork */}}
                                {{- if $incoming_wagon.files -}}
                                  {{- $_ := set $fork "files" (concat $wagon.files $fork.files) -}}
                                {{- end -}}
    
                                {{/* If the wagon has content, we need to load the content as string into a variable
                                     to prevent the $wagon content to be overwritten
                                */}}
                                {{- if $wagon.content -}}
                                  {{- $content := toYaml $wagon.content -}}
                                  {{- $_ := (set $fork "content" (mergeOverwrite (fromYaml ($content)) (default dict $fork.content))) -}}
                                {{- end -}}
  
    
                              {{/* Merge with train */}}
                              {{- else -}}
    
                                {{/* Overwrite Matched */}}
                                {{- $matched = 1 -}}
    
                                {{/* Merge file Properties */}}
                                {{- with $incoming_wagon.files -}}
                                  {{- $_ := set $wagon "files" (concat $wagon.files $incoming_wagon.files) -}}
                                {{- end -}}

                                {{/* Concat Renderers */}}
                                {{- with $incoming_wagon.renderers -}}
                                  {{- $_ := set $wagon "renderers" (concat $wagon.renderers $incoming_wagon.renderers | uniq) -}}
                                {{- end -}}
    
                                {{/* Merge Contents */}}
                                {{- if $incoming_wagon.content -}}
                                  {{- include "lib.utils.dicts.merge" (dict "base" $wagon.content "data" $incoming_wagon.content) -}}
                                {{- end -}}
    
                                {{/* Increase Match Counter */}}
                                {{- $match_count = addf $match_count 1 -}}
    
                              {{- end -}}
                    
                              {{/* Increase Order */}}
                              {{- $order = addf $order 1 -}}
        
                            {{- end -}}
                          {{- end -}}  
                        {{- end -}}
                      {{- end -}}
                    {{- end -}}
                  {{- end -}}
                {{- end -}}
  
                {{/* Append Forks */}}
                {{- if $fork -}}
                 
                   {{/* Append Fork after train iteration */}}
                   {{- $file_train = append $file_train (set (omit $fork "config" "file_id") "fork" "true") -}}

                {{/* Handle unmatched files */}}   
                {{- else if not ($matched) -}}
  
                  {{/* Skip if pattern enabled */}}
                  {{- if not (get $file_cfg (include "helmize.core.defaults.file_cfg.pattern" $)) -}}
  
                    {{/* Skip File if configured */}}
                    {{- if not (eq (get $file_cfg (include "helmize.core.defaults.file_cfg.no_match" $)) "skip") -}}
                      {{- $file_train = append $file_train (omit $incoming_wagon "config" "file_id" | deepCopy) -}}
                      {{- $order = addf $order 1 -}}
                    {{- end -}}
  
                  {{- end -}}
                {{- end -}}
              {{- end -}}  
            {{- else -}}
               {{- $_ := set $return "errors" (list (dict "error" $parsed_content.Error "file" $file_name "trace" $partial_file_content)) -}}
            {{- end -}}
          {{- end -}}
        {{- end -}}

        {{/* Partial Files */}}
        {{- $_ := set $file "partial_files" $partial_files -}}

      {{- else -}}
        {{- $_ := set $return "errors" (list (dict "error" "File not found or empty content" "file" $file_name)) -}}
      {{- end -}}

      {{/* Benchmark */}}
      {{- include "helmize.helpers.ts" (dict "msg" (printf "File Executed") "ctx" $.ts) -}}

    {{- end -}}

    {{/* Conclude Train */}}
    {{- if $file_train -}}

      {{/* Benchmark */}}
      {{- include "helmize.helpers.ts" (dict "msg" "Running enderers" "ctx" $.ts) -}}

      {{/* Run Renderers */}}
      {{- range $wagon := $file_train -}}
        {{- include "helmize.renderers.func.execute" (dict "wagon" $wagon "ctx" $.ctx) -}}
      {{- end -}}

      {{/* Benchmark */}}
      {{- include "helmize.helpers.ts" (dict "msg" "Renderers Done" "ctx" $.ts) -}}

      {{/* Benchmark */}}
      {{- include "helmize.helpers.ts" (dict "msg" "Running Checksums" "ctx" $.ts) -}}

      {{/* Post Manipulations */}}
      {{- range $file := $file_train -}}
        {{- with $file.content -}}
          {{- $_ := set $file "checksum" (sha256sum (toYaml .)) -}}
        {{- end -}}
        {{- range $err := $file.errors -}}
          {{- $_ := set $return "errors" (append $return.errors (set $err "file" $file.id)) -}}
        {{- end -}}
      {{- end -}}

      {{/* Benchmark */}}
      {{- include "helmize.helpers.ts" (dict "msg" "Checksums Done" "ctx" $.ts) -}}

      {{/* Convert to Slice */}}
      {{- $_ := set $return "wagons" $file_train -}} 
    {{- end -}}

    {{/* Return */}}
    {{- printf "%s" (toYaml $return) -}}

  {{- end -}}
{{- end -}}