{% macro json_extract(column_name, key_name, data_type) %}
    {%- if target.type == 'snowflake' -%}
        {{ column_name }}:{{ key_name }}::{{ data_type }}
    {%- else -%}
        ({{ column_name }}->>'{{ key_name }}')::{{ data_type }}
    {%- endif -%}
{% endmacro %}