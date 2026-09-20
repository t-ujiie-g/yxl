///|
#deprecated("Use `==` / `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend Command with Eq::{not_equal, equal}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend Command with @debug.Debug::{to_repr}
