using SeisPlot, SeisAcoustic

work_dir = joinpath(homedir(), "Desktop/tmp_LSRTM");

path_rho = joinpath(work_dir, "physical_model/rho.su");
path_vel = joinpath(work_dir, "physical_model/vel.su");

num_samples = 1911;
num_traces  = 5395;
trace = zeros(Float32, num_samples);
vel   = zeros(Float32, num_samples, num_traces);
rho   = zeros(Float32, num_samples, num_traces);

fid_vel = open(path_vel, "r");
fid_rho = open(path_rho, "r");
idx = [1];
for i = 1 : num_traces
    skip(fid_vel, 240)
    skip(fid_rho, 240)

    read!(fid_vel, trace)
    copyto!(vel, idx[1], trace, 1, num_samples)

    read!(fid_rho, trace)
    copyto!(rho, idx[1], trace, 1, num_samples)
    idx[1] = idx[1] + num_samples
end
close(fid_vel);
close(fid_rho);

# vel = vel[1:1300,1:3700];
# rho = rho[1:1300,1:3700];

vel = vel[1:400,1:1000];
rho = rho[1:400,1:1000];

SeisPlotTX(vel, hbox=1.3*3, wbox=3.7*3, cmap="rainbow", vmin=minimum(vel), vmax=maximum(vel));
SeisPlotTX(rho, hbox=1.3*3, wbox=3.7*3, cmap="rainbow", vmin=minimum(rho), vmax=maximum(rho));

# vertical and horizontal grid size
dz = 6.25; dx = 6.25;

# time step size and maximum modelling length
dt = 0.0005; tmax = 6.0;

# top boundary condition
free_surface = false;

# precision
data_format=Float32;
order=3;

# organize these parameters into a structure
params = TdParams(rho, vel, free_surface, dz, dx, dt, tmax;
                  data_format=data_format, order=order);

# initialize a source
isz = 2; isx = 501;
src = Source(isz, isx, params; amp=100000, fdom=20);

# generate observed data
irx = collect(1:2:params.nx);
irz = 2 * ones(length(irx));
dobs= Recordings(irz, irx, params);

@time multi_step_forward!(dobs, src, params; print_interval=200);


# ==============================================================================
#      generate reflected shot recordings, the direct arrival is removed
# ==============================================================================
function get_reflected_wave()

root = "/Users/wenlei/Desktop/data/marmousi"
path = joinpath(root, "vel.bin")
(hdr, vel) = read_USdata(path)

(nz, nx) = size(vel);
rho = ones(vel);
npml = 20; free_surface = false;

dz = 2.0f0; dx = 2.0f0;
dt = Float32(2.2e-4); fdom = 35.f0;
tmax = 2.0f0;
phi  = PhysicalModel(nz, nx, npml, free_surface, dz, dx, dt, tmax, fdom, rho, vel);
fidMtx1 = FiniteDiffMatrix(phi);

# the finite-difference stencil for remove direct arrival
vmin = minimum(vel); fill!(phi.vel, vmin);
fidMtx2 = FiniteDiffMatrix(phi);

# receiver location
irx = collect(1:2:nx); irz = 1*ones(Int64, length(irx));

# specify source location
isx = collect(10:10:nx-5)
ns  = length(isx)
isz = 2 * ones(Int64, ns)
ot  = zeros(phi.data_format, ns);
amp = phi.data_format(1.e5) * ones(phi.data_format, ns);

# parameters for forward modeling
path =  join([path, "/observations/obs"]);
par = Vector{Dict}(ns)
for i = 1 : ns
    src = Source(isz[i], isx[i], ot[i], amp[i], phi)
    tmp = isx[i]
    path_obs = join([path "_" "$tmp" ".bin"])
    par[i] = Dict(:phi=>phi, :src=>src, :fidMtx1=>fidMtx1, :fidMtx2=>fidMtx2,
                  :irz=>irz, :irx=>irx, :path_obs=>path_obs)
end

pmap(wrap_get_reflections, par)

end

get_reflected_wave()

# examine the recordings
path = "/Users/wenlei/Desktop/data/marmousi/observation/obs_"
i = 990
path_in = join([path "$i" ".bin"]);
(hdr, d) = read_USdata(path_in);
SeisPlot(d, cmap="seismic", pclip=95);



# ==============================================================================
#    get the bounds of source-side wavefield and the source intensity
# ==============================================================================
function get_sourceside_wavefield_bound()

  root = "/Users/wenlei/Desktop/data/marmousi"
  # root = "/home/wgao1/Data/marmousi"
  path = joinpath(root, "marmousi_smooth.bin")
  (hdr, vel) = read_USdata(path)


  (nz, nx) = size(vel);
  rho = ones(vel);
  npml = 20; free_surface = false;


  dz = 2.0f0; dx = 2.0f0;
  dt = Float32(2.2e-4); fdom = 35.f0;
  tmax = 2.0f0;
  phi  = PhysicalModel(nz, nx, npml, free_surface, dz, dx, dt, tmax, fdom, rho, vel);
  fidMtx = FiniteDiffMatrix(phi);


  # receiver location
  irx = collect(1:2:nx); irz = 1*ones(Int64, length(irx));

  # specify source location
  isx = collect(10:10:nx-5)
  ns  = length(isx)
  isz = 2 * ones(Int64, ns)
  ot  = zeros(phi.data_format, ns);
  amp = phi.data_format(1.e5) * ones(phi.data_format, ns);

  # receiver location
  path1 = joinpath(root, "boundary/bnd");
  path2 = joinpath(root, "precondition/str");

  # parameters for forward modeling
par = Vector{Dict}(ns)
for i = 1 : ns
    src = Source(isz[i], isx[i], ot[i], amp[i], phi)
    tmp = isx[i]
    path_bnd = join([path1 "_" "$tmp" ".bin"])
    path_str = join([path2 "_" "$tmp" ".bin"])
    par[i]   = Dict(:phi=>phi, :src=>src, :fidMtx=>fidMtx, :path_bnd=>path_bnd, :path_str=>path_str)
end

path_pre = joinpath(root, "precondition/pre.bin")
wrap_get_wavefield_bound(path_pre, par)

end
get_sourceside_wavefield_bound()


# ==============================================================================
#   RTM or LSRTM or PLSRTM
# ==============================================================================
function RTM(option)

  # root = "/home/wgao1/Data/marmousi"
  root = "/Users/wenlei/Desktop/data/marmousi"
  path = joinpath(root, "marmousi_smooth.bin")
  (hdr, vel0) = read_USdata(path)
  vel = model_smooth(vel0, 20);

  (nz, nx) = size(vel);
  rho = ones(vel);
  npml = 20; free_surface = false;

  dz = 2.0f0; dx = 2.0f0;
  dt = Float32(2.2e-4); fdom = 35.f0;
  tmax = 2.0f0;
  phi  = PhysicalModel(nz, nx, npml, free_surface, dz, dx, dt, tmax, fdom, rho, vel);
  fidMtx = FiniteDiffMatrix(phi);
  fidMtxT= RigidFiniteDiffMatrix(phi);

  # receiver location
  irx = collect(1:2:nx); irz = 1*ones(Int64, length(irx));

  # specify source location
  isx = collect(10:10:nx-5)
  ns  = length(isx)
  isz = 2 * ones(Int64, ns)
  ot  = zeros(phi.data_format, ns);
  amp = phi.data_format(1.e5) * ones(phi.data_format, ns);

  # chop the top part of the model
  model_window = build_model_window(50, 10, phi);

  # intermediate result
  path_bnd = joinpath(root, "boundary/bnd");
  path_pre = joinpath(root, "precondition/pre.bin");
  path_obs = joinpath(root, "observation/obs");
  path_m   = joinpath(root, "model/m.bin");
  path_fwd = joinpath(root, "forward/fwd");
  path_adj = joinpath(root, "adjoint/adj");

  # parameters for forward modeling
  par = pack_parameter_born(phi, isz, isx, ot, amp,
                            irz, irx, fidMtx, fidMtxT, model_window,
                            path_bnd, path_pre, path_obs, path_m, path_fwd, path_adj);


  b = Vector{String}(ns)
  for i = 1 : ns
      b[i] = par[i][:path_obs]
  end

  # RTM
  if option == 1
     wrap_RTM(b, params=par)

  # LSRTM
  elseif option == 2
     path = joinpath(root, "PCGLS")
     (x, convergence) = CGLS(wrap_preconditioned_born_approximation, b;
                        path=path, params=par, print_flag=true)
  end


end
