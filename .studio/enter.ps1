# Habitat studio enter hook — runs automatically on `hab studio enter` and `hab pkg build`.
# Import the chef origin signing keys so packages can be signed without manual intervention.
hab origin key export chef | hab origin key import
hab origin key export core | hab origin key import
hab origin key export --type secret chef | hab origin key import
hab origin key export --type secret core | hab origin key import
