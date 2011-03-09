MODULE sdf_input

  USE sdf_common
  USE mpi

  IMPLICIT NONE

  INTERFACE sdf_read_srl
    MODULE PROCEDURE &
        sdf_read_constant_real, &
        sdf_read_constant_integer, &
        sdf_read_constant_logical, &
        sdf_read_1d_array_real, &
        sdf_read_2d_array_real, &
        sdf_read_1d_array_integer, &
        sdf_read_2d_array_integer, &
        sdf_read_1d_array_logical, &
        sdf_read_2d_array_character
  END INTERFACE sdf_read_srl

CONTAINS

  SUBROUTINE read_header(h)

    TYPE(sdf_file_handle) :: h
    CHARACTER(LEN=4) :: sdf
    INTEGER :: errcode, ierr

    h%current_location = 0
    h%start_location = 0

    ! Read the header
    CALL read_entry_stringlen(h, sdf, 4)

    ! If this isn't SDF_MAGIC then this isn't an SDF file
    IF (sdf .NE. c_sdf_magic) THEN
      CALL MPI_FILE_CLOSE(h%filehandle, errcode)
      IF (h%rank .EQ. h%rank_master) &
          PRINT *, "The specified file is not a valid SDF file"
      CALL MPI_ABORT(h%comm, errcode, ierr)
    ENDIF

    CALL read_entry_int4(h, h%endianness)

    CALL read_entry_int4(h, h%file_version)

    IF (h%file_version .GT. sdf_version) THEN
      IF (h%rank .EQ. h%rank_master) PRINT *, "Version number incompatible"
      CALL MPI_ABORT(h%comm, errcode, ierr)
    ENDIF

    CALL read_entry_int4(h, h%file_revision)

    CALL read_entry_id(h, h%code_name)

    CALL read_entry_int8(h, h%first_block_location)

    CALL read_entry_int8(h, h%summary_location)

    CALL read_entry_int4(h, h%summary_size)

    CALL read_entry_int4(h, h%nblocks)

    CALL read_entry_int4(h, h%block_header_length)

    CALL read_entry_int4(h, h%step)

    CALL read_entry_real8(h, h%time)

    CALL read_entry_int4(h, h%jobid%start_seconds)

    CALL read_entry_int4(h, h%jobid%start_milliseconds)

    CALL read_entry_int4(h, h%string_length)

    CALL read_entry_int4(h, h%code_io_version)

    CALL read_entry_logical(h, h%restart_flag)

    CALL read_entry_logical(h, h%other_domains)

  END SUBROUTINE read_header



  SUBROUTINE sdf_read_header(h, step, time, code_name, code_io_version, &
      restart_flag, other_domains)

    TYPE(sdf_file_handle) :: h
    INTEGER, INTENT(OUT), OPTIONAL :: step
    REAL(num), INTENT(OUT), OPTIONAL :: time
    CHARACTER(LEN=*), INTENT(OUT), OPTIONAL :: code_name
    INTEGER, INTENT(OUT), OPTIONAL :: code_io_version
    LOGICAL, INTENT(OUT), OPTIONAL :: restart_flag, other_domains
    INTEGER :: errcode

    IF (h%done_header) THEN
      IF (h%rank .EQ. h%rank_master) THEN
        PRINT*,'*** WARNING ***'
        PRINT*,'SDF header already read. Ignoring extra call.'
      ENDIF
      RETURN
    ENDIF

    ALLOCATE(h%buffer(c_header_length))

    h%current_location = 0
    IF (h%rank .EQ. h%rank_master) THEN
      CALL MPI_FILE_SEEK(h%filehandle, h%current_location, MPI_SEEK_SET, &
          errcode)
      CALL MPI_FILE_READ(h%filehandle, h%buffer, c_header_length, &
          MPI_CHARACTER, MPI_STATUS_IGNORE, errcode)
    ENDIF

    CALL MPI_BCAST(h%buffer, c_header_length, MPI_CHARACTER, h%rank_master, &
        h%comm, errcode)

    IF (.NOT. ASSOCIATED(h%buffer)) THEN
      CALL MPI_FILE_SET_VIEW(h%filehandle, h%current_location, MPI_BYTE, &
          MPI_BYTE, "native", MPI_INFO_NULL, errcode)
    ENDIF

    ! Read the header

    CALL read_header(h)

    DEALLOCATE(h%buffer)
    NULLIFY(h%buffer)

    IF (h%file_revision .GT. sdf_revision) THEN
      IF (h%rank .EQ. h%rank_master) &
          PRINT *, "Revision number of file is too high. Writing disabled"
      h%writing = .FALSE.
    ENDIF

    h%current_location = h%first_block_location
    h%done_header = .TRUE.

    IF (PRESENT(step)) step = h%step
    IF (PRESENT(time)) time = h%time
    IF (PRESENT(code_io_version)) code_io_version = h%code_io_version
    IF (PRESENT(restart_flag)) restart_flag = h%restart_flag
    IF (PRESENT(other_domains)) other_domains = h%other_domains
    IF (PRESENT(code_name)) CALL safe_copy_string(h%code_name, code_name)

  END SUBROUTINE sdf_read_header



  SUBROUTINE read_block_header(h)

    TYPE(sdf_file_handle) :: h
    TYPE(sdf_block_type), POINTER :: b

    IF (.NOT. ASSOCIATED(h%current_block)) THEN
      IF (h%rank .EQ. h%rank_master) THEN
        PRINT*,'*** WARNING ***'
        PRINT*,'SDF block not initialised. Ignoring call.'
      ENDIF
      RETURN
    ENDIF

    b => h%current_block

    IF (b%done_header) THEN
      h%current_location = b%block_start + h%block_header_length
      RETURN
    ENDIF

    h%current_location = b%block_start

    CALL read_entry_int8(h, b%next_block_location)

    CALL read_entry_int8(h, b%data_location)

    CALL read_entry_id(h, b%id)

    CALL read_entry_int8(h, b%data_length)

    CALL read_entry_int4(h, b%blocktype)

    CALL read_entry_int4(h, b%datatype)

    CALL read_entry_int4(h, b%ndims)

    CALL read_entry_string(h, b%name)

    b%done_header = .TRUE.

    !print*,'block header: b%id: ', TRIM(b%id)
    !print*,'   b%name: ', TRIM(b%name)
    !print*,'   b%blocktype: ', b%blocktype
    !print*,'   b%next_block_location: ', b%next_block_location
    !print*,'   b%data_location: ', b%data_location
    !print*,'   b%datatype: ', b%datatype
    !print*,'   b%ndims: ', b%ndims
    !print*,'   b%data_length: ', b%data_length

  END SUBROUTINE read_block_header



  SUBROUTINE sdf_read_next_block_header(h, id, name, blocktype, ndims, datatype)

    TYPE(sdf_file_handle) :: h
    CHARACTER(LEN=*), INTENT(OUT), OPTIONAL :: id, name
    INTEGER, INTENT(OUT), OPTIONAL :: blocktype, ndims, datatype
    INTEGER :: errcode, ierr
    LOGICAL :: precision_error
    TYPE(sdf_block_type), POINTER :: b

    IF (.NOT. h%done_header) THEN
      IF (h%rank .EQ. h%rank_master) THEN
        PRINT*,'*** ERROR ***'
        PRINT*,'SDF header has not been read. Unable to read block.'
      ENDIF
      RETURN
    ENDIF

    CALL sdf_get_next_block(h)

    b => h%current_block

    IF (.NOT. b%done_header) THEN
      h%current_location = b%block_start

      IF (PRESENT(id)) THEN
        CALL MPI_FILE_SET_VIEW(h%filehandle, h%current_location, MPI_BYTE, &
            MPI_BYTE, "native", MPI_INFO_NULL, errcode)
      ENDIF

      CALL read_block_header(h)

      precision_error = .FALSE.

      IF (b%datatype .EQ. c_datatype_real4) THEN
        b%type_size = 4
        b%mpitype = MPI_REAL4
        IF (num .NE. r4) precision_error = .TRUE.
      ELSE IF (b%datatype .EQ. c_datatype_real8) THEN
        b%type_size = 8
        b%mpitype = MPI_REAL8
        IF (num .NE. r8) precision_error = .TRUE.
      ELSE IF (b%datatype .EQ. c_datatype_integer4) THEN
        b%type_size = 4
        b%mpitype = MPI_INTEGER4
      ELSE IF (b%datatype .EQ. c_datatype_integer8) THEN
        b%type_size = 8
        b%mpitype = MPI_INTEGER8
      ELSE IF (b%datatype .EQ. c_datatype_character) THEN
        b%type_size = 1
        b%mpitype = MPI_CHARACTER
      ELSE IF (b%datatype .EQ. c_datatype_logical) THEN
        b%type_size = 1
        b%mpitype = MPI_CHARACTER
      ENDIF

      IF (precision_error) THEN
        IF (h%rank .EQ. h%rank_master) THEN
          PRINT*,'*** ERROR ***'
          PRINT*,'Precision does not match, recompile code so that', &
              ' sizeof(REAL) = ', h%sof
        ENDIF
        CALL MPI_ABORT(h%comm, errcode, ierr)
      ENDIF

      b%done_header = .TRUE.
    ENDIF

    IF (PRESENT(id)) THEN
      blocktype = b%blocktype
      CALL safe_copy_string(b%id, id)
      CALL safe_copy_string(b%name, name)
      datatype = b%datatype
      ndims = b%ndims
    ENDIF

    h%current_location = b%block_start + h%block_header_length

  END SUBROUTINE sdf_read_next_block_header



  SUBROUTINE sdf_read_run_info(h)

    TYPE(sdf_file_handle) :: h
    INTEGER :: errcode
    TYPE(sdf_block_type), POINTER :: b

    IF (.NOT. ASSOCIATED(h%current_block)) THEN
      IF (h%rank .EQ. h%rank_master) THEN
        PRINT*,'*** ERROR ***'
        PRINT*,'SDF block header has not been read. Ignoring call.'
      ENDIF
      RETURN
    ENDIF

    b => h%current_block
    IF (b%done_info) RETURN

    CALL read_block_header(h)

    IF (.NOT. ASSOCIATED(h%buffer)) THEN
      CALL MPI_FILE_SET_VIEW(h%filehandle, h%current_location, MPI_BYTE, &
          MPI_BYTE, "native", MPI_INFO_NULL, errcode)
    ENDIF

    ! Metadata is
    ! - version   INTEGER(i4)
    ! - revision  INTEGER(i4)
    ! - commit_id CHARACTER(string_length)
    ! - sha1sum   CHARACTER(string_length)
    ! - compmac   CHARACTER(string_length)
    ! - compflag  CHARACTER(string_length)
    ! - defines   INTEGER(i8)
    ! - compdate  INTEGER(i4)
    ! - rundate   INTEGER(i4)
    ! - iodate    INTEGER(i4)

    IF (.NOT. ASSOCIATED(b%run)) ALLOCATE(b%run)

    CALL read_entry_int4(h, b%run%version)

    CALL read_entry_int4(h, b%run%revision)

    CALL read_entry_string(h, b%run%commit_id)

    CALL read_entry_string(h, b%run%sha1sum)

    CALL read_entry_string(h, b%run%compile_machine)

    CALL read_entry_string(h, b%run%compile_flags)

    CALL read_entry_int8(h, b%run%defines)

    CALL read_entry_int4(h, b%run%compile_date)

    CALL read_entry_int4(h, b%run%run_date)

    CALL read_entry_int4(h, b%run%io_date)

    b%done_info = .TRUE.
    b%done_data = .TRUE.

  END SUBROUTINE sdf_read_run_info



  SUBROUTINE sdf_read_constant(h)

    TYPE(sdf_file_handle) :: h
    INTEGER :: errcode
    INTEGER(i4) :: int4
    INTEGER(i8) :: int8
    REAL(r4) :: real4
    REAL(r8) :: real8
    LOGICAL :: logic
    TYPE(sdf_block_type), POINTER :: b

    IF (.NOT. ASSOCIATED(h%current_block)) THEN
      IF (h%rank .EQ. h%rank_master) THEN
        PRINT*,'*** ERROR ***'
        PRINT*,'SDF block header has not been read. Ignoring call.'
      ENDIF
      RETURN
    ENDIF

    b => h%current_block
    IF (b%done_data) RETURN

    CALL read_block_header(h)

    IF (.NOT. ASSOCIATED(h%buffer)) THEN
      CALL MPI_FILE_SET_VIEW(h%filehandle, h%current_location, MPI_BYTE, &
          MPI_BYTE, "native", MPI_INFO_NULL, errcode)
    ENDIF

    IF (b%datatype .EQ. c_datatype_integer4) THEN
      CALL read_entry_int4(h, int4)
      b%const_value = TRANSFER(int4, b%const_value)
    ELSE IF (b%datatype .EQ. c_datatype_integer8) THEN
      CALL read_entry_int8(h, int8)
      b%const_value = TRANSFER(int8, b%const_value)
    ELSE IF (b%datatype .EQ. c_datatype_real4) THEN
      CALL read_entry_real4(h, real4)
      b%const_value = TRANSFER(real4, b%const_value)
    ELSE IF (b%datatype .EQ. c_datatype_real8) THEN
      CALL read_entry_real8(h, real8)
      b%const_value = TRANSFER(real8, b%const_value)
    ELSE IF (b%datatype .EQ. c_datatype_logical) THEN
      CALL read_entry_logical(h, logic)
      b%const_value = TRANSFER(logic, b%const_value)
    ENDIF

    b%done_info = .TRUE.
    b%done_data = .TRUE.

  END SUBROUTINE sdf_read_constant



  SUBROUTINE sdf_read_constant_real(h, value)

    TYPE(sdf_file_handle) :: h
    REAL(num), INTENT(OUT) :: value
    REAL(r4) :: real4
    REAL(r8) :: real8
    TYPE(sdf_block_type), POINTER :: b

    CALL sdf_read_constant(h)

    b => h%current_block

    IF (b%datatype .EQ. c_datatype_real4) THEN
      real4 = TRANSFER(b%const_value, real4)
      value = REAL(real4,num)
    ELSE IF (b%datatype .EQ. c_datatype_real8) THEN
      real8 = TRANSFER(b%const_value, real8)
      value = REAL(real8,num)
    ENDIF

  END SUBROUTINE sdf_read_constant_real



  SUBROUTINE sdf_read_constant_integer(h, value)

    TYPE(sdf_file_handle) :: h
    INTEGER, INTENT(OUT) :: value
    INTEGER(i4) :: integer4
    INTEGER(i8) :: integer8
    TYPE(sdf_block_type), POINTER :: b

    CALL sdf_read_constant(h)

    b => h%current_block

    IF (b%datatype .EQ. c_datatype_integer4) THEN
      integer4 = TRANSFER(b%const_value, integer4)
      value = INT(integer4)
    ELSE IF (b%datatype .EQ. c_datatype_integer8) THEN
      integer8 = TRANSFER(b%const_value, integer8)
      value = INT(integer8)
    ENDIF

  END SUBROUTINE sdf_read_constant_integer



  SUBROUTINE sdf_read_constant_logical(h, value)

    TYPE(sdf_file_handle) :: h
    LOGICAL, INTENT(OUT) :: value
    TYPE(sdf_block_type), POINTER :: b

    CALL sdf_read_constant(h)

    b => h%current_block

    value = TRANSFER(b%const_value, value)

  END SUBROUTINE sdf_read_constant_logical



  SUBROUTINE sdf_read_array_info(h, dims)

    TYPE(sdf_file_handle) :: h
    INTEGER, DIMENSION(:), INTENT(OUT), OPTIONAL :: dims
    INTEGER :: errcode
    TYPE(sdf_block_type), POINTER :: b

    IF (.NOT. ASSOCIATED(h%current_block)) THEN
      IF (h%rank .EQ. h%rank_master) THEN
        PRINT*,'*** ERROR ***'
        PRINT*,'SDF block header has not been read. Ignoring call.'
      ENDIF
      RETURN
    ENDIF

    b => h%current_block
    IF (b%done_info) RETURN

    CALL read_block_header(h)

    IF (.NOT. ASSOCIATED(h%buffer)) THEN
      CALL MPI_FILE_SET_VIEW(h%filehandle, h%current_location, MPI_BYTE, &
          MPI_BYTE, "native", MPI_INFO_NULL, errcode)
    ENDIF

    ! Size of array
    CALL read_entry_array_int4(h, b%dims, b%ndims)

    IF (PRESENT(dims)) dims(1:b%ndims) = b%dims(1:b%ndims)

    b%done_info = .TRUE.

  END SUBROUTINE sdf_read_array_info



  SUBROUTINE sdf_read_1d_array_real(h, values)

    TYPE(sdf_file_handle) :: h
    REAL(num), DIMENSION(:), INTENT(OUT) :: values
    INTEGER, DIMENSION(c_maxdims) :: dims
    INTEGER :: errcode, n1
    TYPE(sdf_block_type), POINTER :: b

    IF (.NOT.ASSOCIATED(h%current_block)) THEN
      IF (h%rank .EQ. h%rank_master) THEN
        PRINT*,'*** ERROR ***'
        PRINT*,'SDF block header has not been read. Ignoring call.'
      ENDIF
      RETURN
    ENDIF

    b => h%current_block
    IF (.NOT. b%done_info) CALL sdf_read_array_info(h, dims)

    h%current_location = b%data_location

    n1 = b%dims(1)

    CALL MPI_FILE_SET_VIEW(h%filehandle, h%current_location, MPI_BYTE, &
        MPI_BYTE, "native", MPI_INFO_NULL, errcode)

    CALL MPI_FILE_READ_ALL(h%filehandle, values, n1, b%mpitype, &
        MPI_STATUS_IGNORE, errcode)

    h%current_location = b%next_block_location
    b%done_data = .TRUE.

  END SUBROUTINE sdf_read_1d_array_real



  SUBROUTINE sdf_read_2d_array_real(h, values)

    TYPE(sdf_file_handle) :: h
    REAL(num), DIMENSION(:,:), INTENT(OUT) :: values
    INTEGER, DIMENSION(c_maxdims) :: dims
    INTEGER :: errcode, i, n1, n2
    TYPE(sdf_block_type), POINTER :: b

    IF (.NOT.ASSOCIATED(h%current_block)) THEN
      IF (h%rank .EQ. h%rank_master) THEN
        PRINT*,'*** ERROR ***'
        PRINT*,'SDF block header has not been read. Ignoring call.'
      ENDIF
      RETURN
    ENDIF

    b => h%current_block
    IF (.NOT. b%done_info) CALL sdf_read_array_info(h, dims)

    h%current_location = b%data_location

    n1 = b%dims(1)
    n2 = b%dims(2)

    CALL MPI_FILE_SET_VIEW(h%filehandle, h%current_location, MPI_BYTE, &
        MPI_BYTE, "native", MPI_INFO_NULL, errcode)

    DO i = 1,n2
      CALL MPI_FILE_READ_ALL(h%filehandle, values(1,i), n1, b%mpitype, &
          MPI_STATUS_IGNORE, errcode)
    ENDDO

    h%current_location = b%next_block_location
    b%done_data = .TRUE.

  END SUBROUTINE sdf_read_2d_array_real



  SUBROUTINE sdf_read_1d_array_integer(h, values)

    TYPE(sdf_file_handle) :: h
    INTEGER, DIMENSION(:), INTENT(OUT) :: values
    INTEGER, DIMENSION(c_maxdims) :: dims
    INTEGER :: errcode, n1
    TYPE(sdf_block_type), POINTER :: b

    IF (.NOT.ASSOCIATED(h%current_block)) THEN
      IF (h%rank .EQ. h%rank_master) THEN
        PRINT*,'*** ERROR ***'
        PRINT*,'SDF block header has not been read. Ignoring call.'
      ENDIF
      RETURN
    ENDIF

    b => h%current_block
    IF (.NOT. b%done_info) CALL sdf_read_array_info(h, dims)

    h%current_location = b%data_location

    n1 = b%dims(1)

    CALL MPI_FILE_SET_VIEW(h%filehandle, h%current_location, MPI_BYTE, &
        MPI_BYTE, "native", MPI_INFO_NULL, errcode)

    CALL MPI_FILE_READ_ALL(h%filehandle, values, n1, b%mpitype, &
        MPI_STATUS_IGNORE, errcode)

    h%current_location = b%next_block_location
    b%done_data = .TRUE.

  END SUBROUTINE sdf_read_1d_array_integer



  SUBROUTINE sdf_read_2d_array_integer(h, values)

    TYPE(sdf_file_handle) :: h
    INTEGER, DIMENSION(:,:), INTENT(OUT) :: values
    INTEGER, DIMENSION(c_maxdims) :: dims
    INTEGER :: errcode, i, n1, n2
    TYPE(sdf_block_type), POINTER :: b

    IF (.NOT.ASSOCIATED(h%current_block)) THEN
      IF (h%rank .EQ. h%rank_master) THEN
        PRINT*,'*** ERROR ***'
        PRINT*,'SDF block header has not been read. Ignoring call.'
      ENDIF
      RETURN
    ENDIF

    b => h%current_block
    IF (.NOT. b%done_info) CALL sdf_read_array_info(h, dims)

    h%current_location = b%data_location

    n1 = b%dims(1)
    n2 = b%dims(2)

    CALL MPI_FILE_SET_VIEW(h%filehandle, h%current_location, MPI_BYTE, &
        MPI_BYTE, "native", MPI_INFO_NULL, errcode)

    DO i = 1,n2
      CALL MPI_FILE_READ_ALL(h%filehandle, values(1,i), n1, b%mpitype, &
          MPI_STATUS_IGNORE, errcode)
    ENDDO

    h%current_location = b%next_block_location
    b%done_data = .TRUE.

  END SUBROUTINE sdf_read_2d_array_integer



  SUBROUTINE sdf_read_1d_array_logical(h, values)

    TYPE(sdf_file_handle) :: h
    LOGICAL, DIMENSION(:), INTENT(OUT) :: values
    CHARACTER(LEN=1), DIMENSION(:), ALLOCATABLE :: cvalues
    INTEGER, DIMENSION(c_maxdims) :: dims
    INTEGER :: errcode, i, n1
    TYPE(sdf_block_type), POINTER :: b

    IF (.NOT.ASSOCIATED(h%current_block)) THEN
      IF (h%rank .EQ. h%rank_master) THEN
        PRINT*,'*** ERROR ***'
        PRINT*,'SDF block header has not been read. Ignoring call.'
      ENDIF
      RETURN
    ENDIF

    b => h%current_block
    IF (.NOT. b%done_info) CALL sdf_read_array_info(h, dims)

    h%current_location = b%data_location

    n1 = b%dims(1)

    CALL MPI_FILE_SET_VIEW(h%filehandle, h%current_location, MPI_BYTE, &
        MPI_BYTE, "native", MPI_INFO_NULL, errcode)

    ALLOCATE(cvalues(n1))

    CALL MPI_FILE_READ_ALL(h%filehandle, cvalues, n1, b%mpitype, &
        MPI_STATUS_IGNORE, errcode)

    DO i = 1,n1
      IF (cvalues(i) .EQ. ACHAR(0)) THEN
        values(i) = .FALSE.
      ELSE
        values(i) = .TRUE.
      ENDIF
    ENDDO

    DEALLOCATE(cvalues)

    h%current_location = b%next_block_location
    b%done_data = .TRUE.

  END SUBROUTINE sdf_read_1d_array_logical



  SUBROUTINE sdf_read_2d_array_character(h, values)

    TYPE(sdf_file_handle) :: h
    CHARACTER(LEN=*), DIMENSION(:), INTENT(OUT) :: values
    INTEGER, DIMENSION(c_maxdims) :: dims
    INTEGER :: errcode, i, n1, n2
    TYPE(sdf_block_type), POINTER :: b

    IF (.NOT.ASSOCIATED(h%current_block)) THEN
      IF (h%rank .EQ. h%rank_master) THEN
        PRINT*,'*** ERROR ***'
        PRINT*,'SDF block header has not been read. Ignoring call.'
      ENDIF
      RETURN
    ENDIF

    b => h%current_block
    IF (.NOT. b%done_info) CALL sdf_read_array_info(h, dims)

    h%current_location = b%data_location

    n1 = b%dims(1)
    n2 = b%dims(2)

    CALL MPI_FILE_SET_VIEW(h%filehandle, h%current_location, MPI_BYTE, &
        MPI_BYTE, "native", MPI_INFO_NULL, errcode)

    DO i = 1,n2
      CALL MPI_FILE_READ_ALL(h%filehandle, values(i), n1, b%mpitype, &
          MPI_STATUS_IGNORE, errcode)
    ENDDO

    h%current_location = b%next_block_location
    b%done_data = .TRUE.

  END SUBROUTINE sdf_read_2d_array_character



  SUBROUTINE sdf_read_stitched_tensor(h)

    TYPE(sdf_file_handle) :: h
    INTEGER :: iloop, errcode
    TYPE(sdf_block_type), POINTER :: b

    IF (.NOT. ASSOCIATED(h%current_block)) THEN
      IF (h%rank .EQ. h%rank_master) THEN
        PRINT*,'*** ERROR ***'
        PRINT*,'SDF block header has not been read. Ignoring call.'
      ENDIF
      RETURN
    ENDIF

    b => h%current_block
    IF (b%done_data) RETURN

    CALL read_block_header(h)

    IF (.NOT. ASSOCIATED(h%buffer)) THEN
      CALL MPI_FILE_SET_VIEW(h%filehandle, h%current_location, MPI_BYTE, &
          MPI_BYTE, "native", MPI_INFO_NULL, errcode)
    ENDIF

    ! Metadata is
    ! - stagger   INTEGER(i4)
    ! - meshid    CHARACTER(id_length)
    ! - varids    ndims*CHARACTER(id_length)

    CALL read_entry_int4(h, b%stagger)

    CALL read_entry_id(h, b%mesh_id)

    ALLOCATE(b%variable_ids(b%ndims))
    DO iloop = 1, b%ndims
      CALL read_entry_id(h, b%variable_ids(iloop))
    ENDDO

    b%done_info = .TRUE.
    b%done_data = .TRUE.

  END SUBROUTINE sdf_read_stitched_tensor



  SUBROUTINE sdf_read_stitched_material(h)

    TYPE(sdf_file_handle) :: h
    INTEGER :: iloop, errcode
    TYPE(sdf_block_type), POINTER :: b

    IF (.NOT. ASSOCIATED(h%current_block)) THEN
      IF (h%rank .EQ. h%rank_master) THEN
        PRINT*,'*** ERROR ***'
        PRINT*,'SDF block header has not been read. Ignoring call.'
      ENDIF
      RETURN
    ENDIF

    b => h%current_block
    IF (b%done_data) RETURN

    CALL read_block_header(h)

    IF (.NOT. ASSOCIATED(h%buffer)) THEN
      CALL MPI_FILE_SET_VIEW(h%filehandle, h%current_location, MPI_BYTE, &
          MPI_BYTE, "native", MPI_INFO_NULL, errcode)
    ENDIF

    ! Metadata is
    ! - stagger   INTEGER(i4)
    ! - meshid    CHARACTER(id_length)
    ! - material_names ndims*CHARACTER(string_length)
    ! - varids    ndims*CHARACTER(id_length)

    CALL read_entry_int4(h, b%stagger)

    CALL read_entry_id(h, b%mesh_id)

    ALLOCATE(b%material_names(b%ndims))
    DO iloop = 1, b%ndims
      CALL read_entry_string(h, b%material_names(iloop))
    ENDDO

    ALLOCATE(b%variable_ids(b%ndims))
    DO iloop = 1, b%ndims
      CALL read_entry_id(h, b%variable_ids(iloop))
    ENDDO

    b%done_info = .TRUE.
    b%done_data = .TRUE.

  END SUBROUTINE sdf_read_stitched_material



  SUBROUTINE sdf_read_stitched_matvar(h)

    TYPE(sdf_file_handle) :: h
    INTEGER :: iloop, errcode
    TYPE(sdf_block_type), POINTER :: b

    IF (.NOT. ASSOCIATED(h%current_block)) THEN
      IF (h%rank .EQ. h%rank_master) THEN
        PRINT*,'*** ERROR ***'
        PRINT*,'SDF block header has not been read. Ignoring call.'
      ENDIF
      RETURN
    ENDIF

    b => h%current_block
    IF (b%done_data) RETURN

    CALL read_block_header(h)

    IF (.NOT. ASSOCIATED(h%buffer)) THEN
      CALL MPI_FILE_SET_VIEW(h%filehandle, h%current_location, MPI_BYTE, &
          MPI_BYTE, "native", MPI_INFO_NULL, errcode)
    ENDIF

    ! Metadata is
    ! - stagger   INTEGER(i4)
    ! - meshid    CHARACTER(id_length)
    ! - matid     CHARACTER(id_length)
    ! - varids    ndims*CHARACTER(id_length)

    CALL read_entry_int4(h, b%stagger)

    CALL read_entry_id(h, b%mesh_id)

    CALL read_entry_id(h, b%material_id)

    ALLOCATE(b%variable_ids(b%ndims))
    DO iloop = 1, b%ndims
      CALL read_entry_id(h, b%variable_ids(iloop))
    ENDDO

    b%done_info = .TRUE.
    b%done_data = .TRUE.

  END SUBROUTINE sdf_read_stitched_matvar



  SUBROUTINE sdf_read_stitched_species(h)

    TYPE(sdf_file_handle) :: h
    INTEGER :: iloop, errcode
    TYPE(sdf_block_type), POINTER :: b

    IF (.NOT. ASSOCIATED(h%current_block)) THEN
      IF (h%rank .EQ. h%rank_master) THEN
        PRINT*,'*** ERROR ***'
        PRINT*,'SDF block header has not been read. Ignoring call.'
      ENDIF
      RETURN
    ENDIF

    b => h%current_block
    IF (b%done_data) RETURN

    CALL read_block_header(h)

    IF (.NOT. ASSOCIATED(h%buffer)) THEN
      CALL MPI_FILE_SET_VIEW(h%filehandle, h%current_location, MPI_BYTE, &
          MPI_BYTE, "native", MPI_INFO_NULL, errcode)
    ENDIF

    ! Metadata is
    ! - stagger   INTEGER(i4)
    ! - meshid    CHARACTER(id_length)
    ! - matid     CHARACTER(id_length)
    ! - matname   CHARACTER(string_length)
    ! - specnames ndims*CHARACTER(string_length)
    ! - varids    ndims*CHARACTER(id_length)

    CALL read_entry_int4(h, b%stagger)

    CALL read_entry_id(h, b%mesh_id)

    CALL read_entry_id(h, b%material_id)

    CALL read_entry_string(h, b%material_name)

    ALLOCATE(b%material_names(b%ndims))
    DO iloop = 1, b%ndims
      CALL read_entry_string(h, b%material_names(iloop))
    ENDDO

    ALLOCATE(b%variable_ids(b%ndims))
    DO iloop = 1, b%ndims
      CALL read_entry_id(h, b%variable_ids(iloop))
    ENDDO

    b%done_info = .TRUE.
    b%done_data = .TRUE.

  END SUBROUTINE sdf_read_stitched_species



  SUBROUTINE read_entry_int4(h, value)

    INTEGER, PARAMETER :: n = 4
    TYPE(sdf_file_handle) :: h
    INTEGER(i4), INTENT(OUT) :: value
    INTEGER :: i, errcode

    IF (ASSOCIATED(h%buffer)) THEN
      i = h%current_location - h%start_location + 1
      value = TRANSFER(h%buffer(i:i+n-1), value)
    ELSE
      CALL MPI_FILE_READ_ALL(h%filehandle, value, 1, MPI_INTEGER4, &
         MPI_STATUS_IGNORE, errcode)
    ENDIF

    h%current_location = h%current_location + n

  END SUBROUTINE read_entry_int4



  SUBROUTINE read_entry_int8(h, value)

    INTEGER, PARAMETER :: n = 8
    TYPE(sdf_file_handle) :: h
    INTEGER(i8), INTENT(OUT) :: value
    INTEGER :: i, errcode

    IF (ASSOCIATED(h%buffer)) THEN
      i = h%current_location - h%start_location + 1
      value = TRANSFER(h%buffer(i:i+n-1), value)
    ELSE
      CALL MPI_FILE_READ_ALL(h%filehandle, value, 1, MPI_INTEGER8, &
         MPI_STATUS_IGNORE, errcode)
    ENDIF

    h%current_location = h%current_location + n

  END SUBROUTINE read_entry_int8



  SUBROUTINE read_entry_real4(h, value)

    INTEGER, PARAMETER :: n = 4
    TYPE(sdf_file_handle) :: h
    REAL(r4), INTENT(OUT) :: value
    INTEGER :: i, errcode

    IF (ASSOCIATED(h%buffer)) THEN
      i = h%current_location - h%start_location + 1
      value = TRANSFER(h%buffer(i:i+n-1), value)
    ELSE
      CALL MPI_FILE_READ_ALL(h%filehandle, value, 1, MPI_REAL4, &
         MPI_STATUS_IGNORE, errcode)
    ENDIF

    h%current_location = h%current_location + n

  END SUBROUTINE read_entry_real4



  SUBROUTINE read_entry_real8(h, value)

    INTEGER, PARAMETER :: n = 8
    TYPE(sdf_file_handle) :: h
    REAL(r8), INTENT(OUT) :: value
    INTEGER :: i, errcode

    IF (ASSOCIATED(h%buffer)) THEN
      i = h%current_location - h%start_location + 1
      value = TRANSFER(h%buffer(i:i+n-1), value)
    ELSE
      CALL MPI_FILE_READ_ALL(h%filehandle, value, 1, MPI_REAL8, &
         MPI_STATUS_IGNORE, errcode)
    ENDIF

    h%current_location = h%current_location + n

  END SUBROUTINE read_entry_real8



  SUBROUTINE read_entry_logical(h, value)

    INTEGER, PARAMETER :: n = 1
    TYPE(sdf_file_handle) :: h
    LOGICAL, INTENT(OUT) :: value
    CHARACTER(LEN=1) :: cvalue
    INTEGER :: i, errcode

    IF (ASSOCIATED(h%buffer)) THEN
      i = h%current_location - h%start_location + 1
      cvalue = TRANSFER(h%buffer(i:i+n-1), cvalue)
    ELSE
      CALL MPI_FILE_READ_ALL(h%filehandle, cvalue, 1, MPI_CHARACTER, &
         MPI_STATUS_IGNORE, errcode)
    ENDIF

    IF (cvalue(1:1) .EQ. ACHAR(1)) THEN
      value = .TRUE.
    ELSE
      value = .FALSE.
    ENDIF

    h%current_location = h%current_location + n

  END SUBROUTINE read_entry_logical



  SUBROUTINE read_entry_stringlen(h, value, n)

    TYPE(sdf_file_handle) :: h
    CHARACTER(LEN=*), INTENT(OUT) :: value
    INTEGER, INTENT(IN) :: n
    INTEGER :: i, j, idx, errcode

    idx = 1

    IF (ASSOCIATED(h%buffer)) THEN
      i = h%current_location - h%start_location + 1
      DO j = 1,n
        value(j:j) = h%buffer(i+j-1)
        IF (value(j:j) .EQ. ACHAR(0)) EXIT
        idx = idx + 1
      ENDDO
    ELSE
      CALL MPI_FILE_READ_ALL(h%filehandle, value, n, MPI_CHARACTER, &
         MPI_STATUS_IGNORE, errcode)
      DO j = 1,n
        IF (value(j:j) .EQ. ACHAR(0)) EXIT
        idx = idx + 1
      ENDDO
    ENDIF

    DO j = idx,n
      value(j:j) = ' '
    ENDDO

    h%current_location = h%current_location + n

  END SUBROUTINE read_entry_stringlen



  SUBROUTINE read_entry_string(h, value)

    TYPE(sdf_file_handle) :: h
    CHARACTER(LEN=*), INTENT(OUT) :: value

    CALL read_entry_stringlen(h, value, h%string_length)

  END SUBROUTINE read_entry_string



  SUBROUTINE read_entry_id(h, value)

    TYPE(sdf_file_handle) :: h
    CHARACTER(LEN=*), INTENT(OUT) :: value

    CALL read_entry_stringlen(h, value, c_id_length)

  END SUBROUTINE read_entry_id



  SUBROUTINE read_entry_array_int4(h, value, nentries)

    INTEGER, PARAMETER :: n = 4
    TYPE(sdf_file_handle) :: h
    INTEGER(i4), INTENT(OUT) :: value(:)
    INTEGER, INTENT(IN) :: nentries
    INTEGER :: i, j, errcode

    IF (ASSOCIATED(h%buffer)) THEN
      i = h%current_location - h%start_location + 1
      DO j = 1, nentries
        value(j) = TRANSFER(h%buffer(i:i+n-1), value(1))
        i = i + n
      ENDDO
    ELSE
      CALL MPI_FILE_READ_ALL(h%filehandle, value, nentries, MPI_INTEGER4, &
         MPI_STATUS_IGNORE, errcode)
    ENDIF

    h%current_location = h%current_location + n * nentries

  END SUBROUTINE read_entry_array_int4



  SUBROUTINE read_entry_array_int8(h, value, nentries)

    INTEGER, PARAMETER :: n = 8
    TYPE(sdf_file_handle) :: h
    INTEGER(i8), INTENT(OUT) :: value(:)
    INTEGER, INTENT(IN) :: nentries
    INTEGER :: i, j, errcode

    IF (ASSOCIATED(h%buffer)) THEN
      i = h%current_location - h%start_location + 1
      DO j = 1, nentries
        value(j) = TRANSFER(h%buffer(i:i+n-1), value(1))
        i = i + n
      ENDDO
    ELSE
      CALL MPI_FILE_READ_ALL(h%filehandle, value, nentries, MPI_INTEGER8, &
         MPI_STATUS_IGNORE, errcode)
    ENDIF

    h%current_location = h%current_location + n * nentries

  END SUBROUTINE read_entry_array_int8



  SUBROUTINE read_entry_array_real4(h, value, nentries)

    INTEGER, PARAMETER :: n = 4
    TYPE(sdf_file_handle) :: h
    REAL(r4), INTENT(OUT) :: value(:)
    INTEGER, INTENT(IN) :: nentries
    INTEGER :: i, j, errcode

    IF (ASSOCIATED(h%buffer)) THEN
      i = h%current_location - h%start_location + 1
      DO j = 1, nentries
        value(j) = TRANSFER(h%buffer(i:i+n-1), value(1))
        i = i + n
      ENDDO
    ELSE
      CALL MPI_FILE_READ_ALL(h%filehandle, value, nentries, MPI_REAL4, &
         MPI_STATUS_IGNORE, errcode)
    ENDIF

    h%current_location = h%current_location + n * nentries

  END SUBROUTINE read_entry_array_real4



  SUBROUTINE read_entry_array_real8(h, value, nentries)

    INTEGER, PARAMETER :: n = 8
    TYPE(sdf_file_handle) :: h
    REAL(r8), INTENT(OUT) :: value(:)
    INTEGER, INTENT(IN) :: nentries
    INTEGER :: i, j, errcode

    IF (ASSOCIATED(h%buffer)) THEN
      i = h%current_location - h%start_location + 1
      DO j = 1, nentries
        value(j) = TRANSFER(h%buffer(i:i+n-1), value(1))
        i = i + n
      ENDDO
    ELSE
      CALL MPI_FILE_READ_ALL(h%filehandle, value, nentries, MPI_REAL8, &
         MPI_STATUS_IGNORE, errcode)
    ENDIF

    h%current_location = h%current_location + n * nentries

  END SUBROUTINE read_entry_array_real8



  SUBROUTINE sdf_safe_read_string(h, string)

    TYPE(sdf_file_handle) :: h
    CHARACTER(LEN=*), INTENT(OUT) :: string

    CALL sdf_safe_read_string_len(h, string, h%string_length)

  END SUBROUTINE sdf_safe_read_string



  SUBROUTINE sdf_safe_skip_string(h)

    TYPE(sdf_file_handle) :: h
    INTEGER(KIND=MPI_OFFSET_KIND) :: offset
    INTEGER :: errcode

    offset = h%string_length
    CALL MPI_FILE_SEEK_SHARED(h%filehandle, offset, MPI_SEEK_CUR, errcode)

  END SUBROUTINE sdf_safe_skip_string



  SUBROUTINE sdf_safe_read_id(h, string)

    TYPE(sdf_file_handle) :: h
    CHARACTER(LEN=*), INTENT(OUT) :: string

    CALL sdf_safe_read_string_len(h, string, c_id_length)

  END SUBROUTINE sdf_safe_read_id



  SUBROUTINE sdf_safe_read_string_len(h, string, length)

    TYPE(sdf_file_handle) :: h
    CHARACTER(LEN=*), INTENT(OUT) :: string
    INTEGER, INTENT(IN) :: length
    CHARACTER(LEN=length) :: string_l
    INTEGER :: string_len, errcode

    string_len = LEN(string)

    CALL MPI_FILE_READ_ALL(h%filehandle, string_l, length, &
        MPI_CHARACTER, MPI_STATUS_IGNORE, errcode)

    string = ' '
    string = string_l(1:MIN(string_len, length))

  END SUBROUTINE sdf_safe_read_string_len

END MODULE sdf_input