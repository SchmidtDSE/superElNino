import xarray as xr

import climate_tools as ct

units = ct.load_units()
map_files = sorted(ct.processed_dir.glob('*/*_water_year_pr.nc'))

for path in map_files:
    water_year_pr = xr.open_dataarray(path).load()
    summary = ct.summarise_units(water_year_pr, units).assign(
        dataset=water_year_pr.attrs['dataset'],
        model=water_year_pr.attrs['model'])
    out_path = path.with_name(path.name.replace('.nc', '_units.csv'))
    summary.to_csv(out_path, index=False)
    print(f'summarised {path.name}')
