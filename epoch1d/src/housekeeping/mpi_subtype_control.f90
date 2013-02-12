MODULE mpi_subtype_control

  !----------------------------------------------------------------------------
  ! This module contains the subroutines which create the subtypes used in
  ! IO
  !----------------------------------------------------------------------------

  USE mpi
  USE shared_data

  IMPLICIT NONE

CONTAINS

  !----------------------------------------------------------------------------
  ! get_total_local_particles - Returns the number of particles on this
  ! processor.
  !----------------------------------------------------------------------------

  FUNCTION get_total_local_particles()

    ! This subroutine describes the total number of particles on the current
    ! processor. It simply sums over every particle species

    INTEGER(i8) :: get_total_local_particles
    INTEGER :: ispecies

    get_total_local_particles = 0
    DO ispecies = 1, n_species
      get_total_local_particles = get_total_local_particles &
          + species_list(ispecies)%attached_list%count
    ENDDO

  END FUNCTION get_total_local_particles



  !----------------------------------------------------------------------------
  ! CreateSubtypes - Creates the subtypes used by the main output routines
  ! Run just before output takes place
  !----------------------------------------------------------------------------

  SUBROUTINE create_subtypes(dump_code)

    ! This subroutines creates the MPI types which represent the data for the
    ! field and particles data. It is used when writing data
    INTEGER, INTENT(IN) :: dump_code
    INTEGER :: n_dump_species, ispecies, index

    ! count the number of dumped particles of each species
    n_dump_species = 0
    DO ispecies = 1, n_species
      IF (IAND(species_list(ispecies)%dumpmask, dump_code) .NE. 0 &
          .OR. IAND(dump_code, c_io_restartable) .NE. 0) THEN
        n_dump_species = n_dump_species + 1
      ENDIF
    ENDDO

    ! Actually create the subtypes
    subtype_field = create_current_field_subtype()
    subarray_field = create_current_field_subarray(ng)
    subarray_field_big = create_current_field_subarray(jng)

    subtype_field_r4 = create_current_field_subtype(MPI_REAL4)
    subarray_field_r4 = create_current_field_subarray(ng, MPI_REAL4)
    subarray_field_big_r4 = create_current_field_subarray(jng, MPI_REAL4)

  END SUBROUTINE create_subtypes



  !----------------------------------------------------------------------------
  ! Frees the subtypes created by create_subtypes
  !----------------------------------------------------------------------------

  SUBROUTINE free_subtypes

    CALL MPI_TYPE_FREE(subtype_field, errcode)
    CALL MPI_TYPE_FREE(subarray_field, errcode)
    CALL MPI_TYPE_FREE(subarray_field_big, errcode)

    CALL MPI_TYPE_FREE(subtype_field_r4, errcode)
    CALL MPI_TYPE_FREE(subarray_field_r4, errcode)
    CALL MPI_TYPE_FREE(subarray_field_big_r4, errcode)

  END SUBROUTINE free_subtypes



  !----------------------------------------------------------------------------
  ! create_current_field_subtype - Creates the subtype corresponding to the
  ! current load balanced geometry
  !----------------------------------------------------------------------------

  FUNCTION create_current_field_subtype(basetype_in)

    INTEGER :: create_current_field_subtype
    INTEGER, OPTIONAL, INTENT(IN) :: basetype_in
    INTEGER :: basetype

    IF (PRESENT(basetype_in)) THEN
      basetype = basetype_in
    ELSE
      basetype = mpireal
    ENDIF

    create_current_field_subtype = &
        create_field_subtype(basetype, nx, nx_global_min)

  END FUNCTION create_current_field_subtype



  !----------------------------------------------------------------------------
  ! create_current_field_subarray - Creates the subarray corresponding to the
  ! current load balanced geometry
  !----------------------------------------------------------------------------

  FUNCTION create_current_field_subarray(ng, basetype_in)

    INTEGER :: create_current_field_subarray
    INTEGER, INTENT(IN) :: ng
    INTEGER, OPTIONAL, INTENT(IN) :: basetype_in
    INTEGER :: basetype

    IF (PRESENT(basetype_in)) THEN
      basetype = basetype_in
    ELSE
      basetype = mpireal
    ENDIF

    create_current_field_subarray = create_field_subarray(basetype, ng, nx)

  END FUNCTION create_current_field_subarray



  !----------------------------------------------------------------------------
  ! create_subtypes_for_load - Creates subtypes when the code loads initial
  ! conditions from a file
  !----------------------------------------------------------------------------

  SUBROUTINE create_subtypes_for_load(species_subtypes)

    ! This subroutines creates the MPI types which represent the data for the
    ! field and particles data. It is used when reading data.

    INTEGER, POINTER :: species_subtypes(:)
    INTEGER :: i

    subtype_field = create_current_field_subtype()
    subarray_field = create_current_field_subarray(ng)
    subarray_field_big = create_current_field_subarray(jng)

    subtype_field_r4 = create_current_field_subtype(MPI_REAL4)
    subarray_field_r4 = create_current_field_subarray(ng, MPI_REAL4)
    subarray_field_big_r4 = create_current_field_subarray(jng, MPI_REAL4)

    ALLOCATE(species_subtypes(n_species))
    DO i = 1,n_species
      species_subtypes(i) = &
          create_particle_subtype(species_list(i)%attached_list%count)
    ENDDO

  END SUBROUTINE create_subtypes_for_load



  !----------------------------------------------------------------------------
  ! free_subtypes_for_load - Frees subtypes created by create_subtypes_for_load
  !----------------------------------------------------------------------------

  SUBROUTINE free_subtypes_for_load(species_subtypes)

    INTEGER, POINTER :: species_subtypes(:)
    INTEGER :: i

    CALL MPI_TYPE_FREE(subtype_field, errcode)
    CALL MPI_TYPE_FREE(subarray_field, errcode)
    CALL MPI_TYPE_FREE(subarray_field_big, errcode)

    CALL MPI_TYPE_FREE(subtype_field_r4, errcode)
    CALL MPI_TYPE_FREE(subarray_field_r4, errcode)
    CALL MPI_TYPE_FREE(subarray_field_big_r4, errcode)
    DO i = 1,n_species
      CALL MPI_TYPE_FREE(species_subtypes(i), errcode)
    ENDDO
    DEALLOCATE(species_subtypes)

  END SUBROUTINE free_subtypes_for_load



  !----------------------------------------------------------------------------
  ! create_particle_subtype - Creates a subtype representing the local
  ! particles
  !----------------------------------------------------------------------------

  FUNCTION create_particle_subtype(npart_in) RESULT(subtype)

    INTEGER(i8), INTENT(IN) :: npart_in
    INTEGER(i8), DIMENSION(1) :: npart_local
    INTEGER(i8), DIMENSION(:), ALLOCATABLE :: npart_each_rank
    INTEGER, DIMENSION(3) :: lengths, types
    INTEGER(KIND=MPI_ADDRESS_KIND), DIMENSION(3) :: disp
    INTEGER(KIND=MPI_ADDRESS_KIND) :: particles_to_skip, total_particles
    INTEGER :: i, subtype, basetype, typesize

    npart_local = npart_in

    ALLOCATE(npart_each_rank(nproc))

    ! Create the subarray for the particles in this problem: subtype decribes
    ! where this process's data fits into the global picture.
    CALL MPI_ALLGATHER(npart_local, 1, MPI_INTEGER8, &
        npart_each_rank, 1, MPI_INTEGER8, comm, errcode)

    particles_to_skip = 0
    DO i = 1, rank
      particles_to_skip = particles_to_skip + npart_each_rank(i)
    ENDDO

    total_particles = particles_to_skip
    DO i = rank+1, nproc
      total_particles = total_particles + npart_each_rank(i)
    ENDDO

    DEALLOCATE(npart_each_rank)

    basetype = mpireal
    CALL MPI_TYPE_SIZE(basetype, typesize, errcode)

    ! If npart_in is bigger than an integer then the data will not
    ! get written/read properly. This would require about 48GB per processor
    ! so it is unlikely to be a problem any time soon.
    lengths(1) = 1
    lengths(2) = INT(npart_in)
    lengths(3) = 1
    disp(1) = 0
    disp(2) = particles_to_skip * typesize
    disp(3) = total_particles * typesize
    types(1) = MPI_LB
    types(2) = basetype
    types(3) = MPI_UB

    subtype = 0
    CALL MPI_TYPE_CREATE_STRUCT(3, lengths, disp, types, subtype, errcode)
    CALL MPI_TYPE_COMMIT(subtype, errcode)

  END FUNCTION create_particle_subtype



  !----------------------------------------------------------------------------
  ! create_field_subtype - Creates a subtype representing the local processor
  ! for any arbitrary arrangement of an array covering the entire spatial
  ! domain. Only used directly during load balancing
  !----------------------------------------------------------------------------

  FUNCTION create_field_subtype(basetype, nx_local, cell_start_x_local)

    INTEGER, INTENT(IN) :: basetype
    INTEGER, INTENT(IN) :: nx_local
    INTEGER, INTENT(IN) :: cell_start_x_local
    INTEGER :: create_field_subtype
    INTEGER, DIMENSION(c_ndims) :: n_local, n_global, start

    n_local = nx_local
    n_global = nx_global
    start = cell_start_x_local

    create_field_subtype = &
        create_1d_array_subtype(basetype, n_local, n_global, start)

  END FUNCTION create_field_subtype



  !----------------------------------------------------------------------------
  ! create_1d_array_subtype - Creates a subtype representing the local fraction
  ! of a completely arbitrary 1D array. Does not assume anything about the
  ! domain at all.
  !----------------------------------------------------------------------------

  FUNCTION create_1d_array_subtype(basetype, n_local, n_global, start) &
      RESULT(vec1d_sub)

    INTEGER, INTENT(IN) :: basetype
    INTEGER, DIMENSION(1), INTENT(IN) :: n_local
    INTEGER, DIMENSION(1), INTENT(IN) :: n_global
    INTEGER, DIMENSION(1), INTENT(IN) :: start
    INTEGER, DIMENSION(3) :: lengths, types
    INTEGER(KIND=MPI_ADDRESS_KIND) :: disp(3), starts(1)
    INTEGER :: vec1d, vec1d_sub, typesize

    vec1d = MPI_DATATYPE_NULL
    CALL MPI_TYPE_CONTIGUOUS(n_local(1), basetype, vec1d, errcode)
    CALL MPI_TYPE_COMMIT(vec1d, errcode)

    CALL MPI_TYPE_SIZE(basetype, typesize, errcode)
    starts = start - 1
    lengths = 1

    disp(1) = 0
    disp(2) = typesize * starts(1)
    disp(3) = typesize * n_global(1)
    types(1) = MPI_LB
    types(2) = vec1d
    types(3) = MPI_UB

    vec1d_sub = MPI_DATATYPE_NULL
    CALL MPI_TYPE_CREATE_STRUCT(3, lengths, disp, types, vec1d_sub, errcode)
    CALL MPI_TYPE_COMMIT(vec1d_sub, errcode)

    CALL MPI_TYPE_FREE(vec1d, errcode)

  END FUNCTION create_1d_array_subtype



  !----------------------------------------------------------------------------
  ! create_2d_array_subtype - Creates a subtype representing the local fraction
  ! of a completely arbitrary 2D array. Does not assume anything about the
  ! domain at all.
  !----------------------------------------------------------------------------

  FUNCTION create_2d_array_subtype(basetype, n_local, n_global, start) &
      RESULT(vec2d_sub)

    INTEGER, INTENT(IN) :: basetype
    INTEGER, DIMENSION(2), INTENT(IN) :: n_local
    INTEGER, DIMENSION(2), INTENT(IN) :: n_global
    INTEGER, DIMENSION(2), INTENT(IN) :: start
    INTEGER, DIMENSION(3) :: lengths, types
    INTEGER(KIND=MPI_ADDRESS_KIND) :: disp(3), starts(2)
    INTEGER :: vec2d, vec2d_sub, typesize

    vec2d = MPI_DATATYPE_NULL
    CALL MPI_TYPE_VECTOR(n_local(2), n_local(1), n_global(1), basetype, &
        vec2d, errcode)
    CALL MPI_TYPE_COMMIT(vec2d, errcode)

    CALL MPI_TYPE_SIZE(basetype, typesize, errcode)
    starts = start - 1
    lengths = 1

    disp(1) = 0
    disp(2) = typesize * (starts(1) + n_global(1) * starts(2))
    disp(3) = typesize * n_global(1) * n_global(2)
    types(1) = MPI_LB
    types(2) = vec2d
    types(3) = MPI_UB

    vec2d_sub = MPI_DATATYPE_NULL
    CALL MPI_TYPE_CREATE_STRUCT(3, lengths, disp, types, vec2d_sub, errcode)
    CALL MPI_TYPE_COMMIT(vec2d_sub, errcode)

    CALL MPI_TYPE_FREE(vec2d, errcode)

  END FUNCTION create_2d_array_subtype



  !----------------------------------------------------------------------------
  ! create_3d_array_subtype - Creates a subtype representing the local fraction
  ! of a completely arbitrary 3D array. Does not assume anything about the
  ! domain at all.
  !----------------------------------------------------------------------------

  FUNCTION create_3d_array_subtype(basetype, n_local, n_global, start) &
      RESULT(vec3d_sub)

    INTEGER, INTENT(IN) :: basetype
    INTEGER, DIMENSION(3), INTENT(IN) :: n_local
    INTEGER, DIMENSION(3), INTENT(IN) :: n_global
    INTEGER, DIMENSION(3), INTENT(IN) :: start
    INTEGER, DIMENSION(3) :: lengths, types
    INTEGER(KIND=MPI_ADDRESS_KIND) :: disp(3), starts(3)
    INTEGER :: vec2d, vec2d_sub
    INTEGER :: vec3d, vec3d_sub, typesize

    vec2d = MPI_DATATYPE_NULL
    CALL MPI_TYPE_VECTOR(n_local(2), n_local(1), n_global(1), basetype, &
        vec2d, errcode)
    CALL MPI_TYPE_COMMIT(vec2d, errcode)

    CALL MPI_TYPE_SIZE(basetype, typesize, errcode)
    starts = start - 1
    lengths = 1

    disp(1) = 0
    disp(2) = typesize * (starts(1) + n_global(1) * starts(2))
    disp(3) = typesize * n_global(1) * n_global(2)
    types(1) = MPI_LB
    types(2) = vec2d
    types(3) = MPI_UB

    vec2d_sub = MPI_DATATYPE_NULL
    CALL MPI_TYPE_CREATE_STRUCT(3, lengths, disp, types, vec2d_sub, errcode)
    CALL MPI_TYPE_COMMIT(vec2d_sub, errcode)

    vec3d = MPI_DATATYPE_NULL
    CALL MPI_TYPE_CONTIGUOUS(n_local(3), vec2d_sub, vec3d, errcode)
    CALL MPI_TYPE_COMMIT(vec3d, errcode)

    disp(1) = 0
    disp(2) = typesize * n_global(1) * n_global(2) * starts(3)
    disp(3) = typesize * n_global(1) * n_global(2) * n_global(3)
    types(1) = MPI_LB
    types(2) = vec3d
    types(3) = MPI_UB

    vec3d_sub = MPI_DATATYPE_NULL
    CALL MPI_TYPE_CREATE_STRUCT(3, lengths, disp, types, vec3d_sub, errcode)
    CALL MPI_TYPE_COMMIT(vec3d_sub, errcode)

    CALL MPI_TYPE_FREE(vec2d, errcode)
    CALL MPI_TYPE_FREE(vec2d_sub, errcode)
    CALL MPI_TYPE_FREE(vec3d, errcode)

  END FUNCTION create_3d_array_subtype



  FUNCTION create_field_subarray(basetype, ng, n1, n2, n3)

    INTEGER, INTENT(IN) :: basetype, ng, n1
    INTEGER, INTENT(IN), OPTIONAL :: n2, n3
    INTEGER, DIMENSION(3) :: n_local, n_global, start
    INTEGER :: i, ndim, create_field_subarray

    n_local(1) = n1
    ndim = 1
    IF (PRESENT(n2)) THEN
      n_local(2) = n2
      ndim = 2
    ENDIF
    IF (PRESENT(n3)) THEN
      n_local(3) = n3
      ndim = 3
    ENDIF

    DO i = 1, ndim
      start(i) = 1 + ng
      n_global(i) = n_local(i) + 2 * ng
    ENDDO

    IF (PRESENT(n3)) THEN
      create_field_subarray = &
          create_3d_array_subtype(basetype, n_local, n_global, start)
    ELSE IF (PRESENT(n2)) THEN
      create_field_subarray = &
          create_2d_array_subtype(basetype, n_local, n_global, start)
    ELSE
      create_field_subarray = &
          create_1d_array_subtype(basetype, n_local, n_global, start)
    ENDIF

  END FUNCTION create_field_subarray

END MODULE mpi_subtype_control
