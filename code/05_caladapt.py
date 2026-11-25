import re

import intake
import xarray as xr

import climate_tools as ct

catalog_url = 'https://cadcat.s3.amazonaws.com/cae-collection.json'
catalog = intake.open_esm_datastore(catalog_url).df
runs = catalog.query(
    "activity_id == 'LOCA2' and table_id == 'mon' and variable_id == 'pr' and "
    "experiment_id == 'historical' and grid_label == 'd03'")


def realisation(member_id):
    return int(re.match(r'r(\d+)', member_id).group(1))


first_runs = (runs.assign(r=runs.member_id.map(realisation))
              .sort_values(['source_id', 'r']).groupby('source_id').head(1))

for run in first_runs.itertuples():
    rate = xr.open_zarr(run.path, storage_options={'anon': True},
                        consolidated=True)['pr']
    rate = ct.crop_to_mojave(ct.standardise_coordinates(rate)).load()
    monthly_mm = ct.monthly_total_mm(rate)
    model = f'{run.source_id}_{run.member_id}'
    ct.save_water_year_map(ct.water_year_totals(monthly_mm), 'caladapt_loca2',
                           model)
