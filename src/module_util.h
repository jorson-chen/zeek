//
// These functions are used by both Bro and bifcl.
//

#pragma once

#include <string>

static const char* GLOBAL_MODULE_NAME = "GLOBAL";

extern std::string extract_module_name(std::string_view name);
extern std::string extract_var_name(std::string_view name);
extern std::string normalized_module_name(std::string_view module_name); // w/o ::

// Concatenates module_name::var_name unless var_name is already fully
// qualified, in which case it is returned unmodified.
extern std::string make_full_var_name(std::string_view module_name, std::string_view var_name);
