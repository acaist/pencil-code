! $Id$
!
! This module is used to solve the equation of supersaturation
! for either the Smoluchowski approach or the swarm model.
!
!** AUTOMATIC CPARAM.INC GENERATION ****************************
! Declare (for generation of cparam.inc) the number of f array
! variables and auxiliary variables added by this module
!
! CPARAM logical, parameter :: lsupersat = .true.
!
! MVAR CONTRIBUTION 1
! MAUX CONTRIBUTION 0
!
! PENCILS PROVIDED ssat
! PENCILS PROVIDED gssat(3); ugssat
! PENCILS PROVIDED del2ssat
! PENCILS PROVIDED tausupersat
! PENCILS PROVIDED condensationRate
!
!***************************************************************
module Supersat
!
  use Cdata
  use Cparam
  use Messages
!
  implicit none
!
  include 'supersat.h'
!
! Define local variables in this special module, not in "Cdata.f90"
  integer :: icondensationRate=0
!  Init parameters.
!
  real :: ssat_const=0., amplssat=0., widthssat=0.
  real :: lnTT_const=0.
  logical :: nosupersat=.false., reinitialize_ssat=.false.
  character (len=labellen) :: initssat='nothing'
  character (len=labellen) :: initlnTT='nothing'
!
  namelist /supersat_init_pars/ &
           initssat, ssat_const, amplssat, widthssat, &
           initlnTT, lnTT_const
!
!  Run parameters.
!
  real :: thermal_diff=0.0
  real :: supersat_diff=0.0
  real :: supersat_sink=0.0
  real :: vapor_mixing_ratio_qvs=0.0
  real :: updraft=0.0
  real :: A1=0.0
  real :: latent_heat=0.0, cp=0.0
  real, dimension(3) :: gradssat0=(/0.0,0.0,0.0/)
  real, dimension(3) :: gradlnTT0=(/0.0,0.0,0.0/)
  real :: c1, c2, Rv, rho0
  real, dimension(nx) :: es_T, qvs_T 
  logical :: lsupersat_sink=.false., Rsupersat_sink=.false.,lupdraft=.false.
  logical :: lupw_ssat=.false., lcondensation_rate=.false.

  namelist /supersat_run_pars/ &
      lupw_ssat, lsupersat_sink, Rsupersat_sink, supersat_sink, &
      supersat_diff, gradssat0, lcondensation_rate, vapor_mixing_ratio_qvs, &
      lupdraft, updraft, A1, latent_heat, cp, &
      c1, c2, Rv, rho0, &
      thermal_diff, gradlnTT0
!
! Declare index of new variables in f array
!
!  integer :: issat=0
! XY: type of "issat" is defined in "cdata.f90"
!
!  Diagnostics variables
!
  integer :: idiag_ssatrms=0, idiag_ssatmax=0, idiag_ssatmin=0
  integer :: idiag_uxssatm=0, idiag_uyssatm=0, idiag_uzssatm=0
  integer :: idiag_tausupersatrms=0, idiag_tausupersatmax=0, idiag_tausupersatmin=0
  integer :: idiag_condensationRaterms=0, idiag_condensationRatemax=0,idiag_condensationRatemin=0
  integer :: idiag_temperaturerms=0, idiag_temperaturemax=0,idiag_temperaturemin=0
  integer :: idiag_supersaturationrms=0, idiag_supersaturationmax=0,idiag_supersaturationmin=0
!
  contains
!***********************************************************************
    subroutine register_supersat()
!
!  Initialise the ssat variable and increase nvar accordingly
!
!   3-jun-16/xiangyu: adapted from pscalar_nolog
!
      use FArrayManager
!
      call farray_register_pde('ssat', issat)

!NILS: issat is given a value in farray_register_pde, then it can not be
!NILS: set to zero right below. I have therefore commented out this line.
!      issat = 0                 ! needed for idl
!
!
!  Identify version number.
!
      if (lroot) call svn_id( &
          "$Id$")
!
    endsubroutine register_supersat
!***********************************************************************
    subroutine initialize_supersat(f)
!
!  Perform any necessary post-parameter read initialization
!  Since the passive scalar is often used for diagnostic purposes
!  one may want to reinitialize it to its initial distribution.
!
      real, dimension (mx,my,mz,mfarray) :: f
!
      if (lroot) print*, 'Supersaturation routine'
!
!  set to zero and then call the same initial condition
!  that was used in start.csh
!
      if (reinitialize_ssat) then
        f(:,:,:,issat)=0.
        call init_ssat(f)
      endif
!
    endsubroutine initialize_supersat
!
!***********************************************************************
    subroutine init_ssat(f)
!
!  initialise passive scalar field; called from start.f90
!
      use Sub
      use Initcond
!
      real, dimension (mx,my,mz,mfarray) :: f
      real :: mudry1, muvap1
      integer :: l
!
      select case (initssat)
        case ('nothing')
        case ('zero'); f(:,:,:,issat)=0.0
        case ('constant'); f(:,:,:,issat)=ssat_const
        case ('tanhx')
          do m=m1,m2;do n=n1,n2
             f(:,m,n,issat)=ssat_const+amplssat*tanh(x/widthssat)
          enddo;enddo
        case ('tanhz')
          do l=l1,l2; do m=m1,m2
             f(l,m,:,issat)=ssat_const+amplssat*tanh(z/widthssat)
          enddo;enddo
!
!  Catch unknown values.
!
        case default
          call fatal_error('initssat','initssat value not recognised')
      endselect
!
! Temperature, initial profile
      select case (initlnTT)
        case ('nothing')
        case ('zero'); f(:,:,:,ilnTT)=0.0
        case ('constant'); f(:,:,:,ilnTT)=lnTT_const
        case default
          call fatal_error('initlnTT','initlnTT value not recognised')
      endselect
!
!  modify the density to have lateral pressure equilibrium
!
!print*,'AXEL6', mudry1, muvap1
       mudry1=1./29.
       muvap1=1./18.
       f(:,:,:,ilnrho)=f(:,:,:,ilnrho)-alog((1-f(:,:,:,issat))*mudry1+f(:,:,:,issat)*muvap1)
!XX
!
    endsubroutine init_ssat
!***********************************************************************
    subroutine pencil_criteria_supersat()
!
!  All pencils that the Supersat module depends on are specified here.
!
      integer :: i
!
!  ssat itself always
!
      lpenc_requested(i_ssat)=.true.
      if (ldustdensity) then
!       lpenc_requested(i_nd)=.true.
!       lpenc_requested(i_ad)=.true.
      endif
!
!  background gradient 
!
      do i=1,3
        if (gradssat0(i)/=0.) lpenc_requested(i_uu)=.true.
      enddo
!
      if (lsupersat_sink) then 
        lpenc_requested(i_ssat)=.true.
        lpenc_requested(i_tausupersat)=.true.
      endif
      if (supersat_diff/=0.) lpenc_requested(i_del2ssat)=.true.
 
      lpenc_diagnos(i_ssat)=.true.
!     
!  temperature
      if (ltemperature) lpenc_requested(i_lnTT)=.true.
      if (thermal_diff/=0.) lpenc_requested(i_del2lnTT)=.true.
      do i=1,3
        if (gradlnTT0(i)/=0.) lpenc_requested(i_uu)=.true.
      enddo
!
    endsubroutine pencil_criteria_supersat
!***********************************************************************
    subroutine pencil_interdep_supersat(lpencil_in)
!  Interdependency among pencils provided by the Pscalar module
!  is specified here.
      logical, dimension(npencils) :: lpencil_in
!
      lpencil_in(i_ssat)=.true.
      lpencil_in(i_ugssat)=.true.
      if (lpencil_in(i_ugssat)) then
        lpencil_in(i_uu)=.true.
        lpencil_in(i_gssat)=.true.
      endif
      lpencil_in(i_tausupersat)=.true.
      lpencil_in(i_condensationRate)=.true.
    endsubroutine pencil_interdep_supersat
!**********************************************************************
    subroutine calc_pencils_supersat(f,p)
!
!  Calculate supersat Pencils.
!  Most basic pencils should come first, as others may depend on them.
!
      use Sub
!
      real, dimension (mx,my,mz,mfarray) :: f
      type (pencil_case) :: p
      integer :: j
!
      intent(in) :: f
      intent(inout) :: p
!
! ssat
      if (lpencil(i_ssat)) p%ssat=f(l1:l2,m,n,issat)
!
!  Compute gssat. Add imposed spatially constant gradient of ssat.
!  (This only makes sense for periodic boundary conditions.)
!
      if (lpencil(i_gssat)) then
        call grad(f,issat,p%gssat)
        do j=1,3
          if (gradssat0(j)/=0.) p%gssat(:,j)=p%gssat(:,j)+gradssat0(j)
        enddo
      endif
! ugssat
      if (lpencil(i_ugssat)) then
        call u_dot_grad(f,issat,p%gssat,p%uu,p%ugssat,UPWIND=lupw_ssat)
      endif
! del2ssat
      if (lpencil(i_del2ssat)) then
        call del2(f,issat,p%del2ssat)
      endif
!
! temperature
      if (lpencil(i_lnTT)) p%lnTT=f(l1:l2,m,n,ilnTT)
! Compute glnTT
      if (lpencil(i_glnTT)) then
        call grad(f,ilnTT,p%glnTT)
        do j=1,3
          if (gradlnTT0(j)/=0.) p%glnTT(:,j)=p%glnTT(:,j)+gradlnTT0(j)
        enddo
      endif
! uglnTT
      if (lpencil(i_uglnTT)) then
        call u_dot_grad(f,ilnTT,p%glnTT,p%uu,p%uglnTT)
      endif
! del2lnTT
      if (lpencil(i_del2lnTT)) then
        call del2(f,ilnTT,p%del2lnTT)
      endif
!
    endsubroutine calc_pencils_supersat
!***********************************************************************
    subroutine dssat_dt(f,df,p)
!
!  Active scalar evolution for supersation
!  Calculate dssat/dt=-uu.gssat + supersat_diff*[del2ssat + glnrho.gssat].
!
!  27-may-16/xiangyu: adapted from pscalar_nolog
!   4-sep-16/axel: added more diagnostics
!
      use Diagnostics
!      use Dustdensity
      use Sub
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx,my,mz,mvar) :: df
      type (pencil_case) :: p
!
      real, dimension (nx) :: diff_op,diff_op2,bump,gcgu
      real, dimension (nx) :: radius_sum, condensation_rate_Cd, qv, supersaturation
      real :: ssat_xyaver
      real :: lam_gradC_fact=1., om_gradC_fact=1., gradC_fact=1.
      integer, parameter :: nxy=nxgrid*nygrid
      integer :: k
!
      intent(in)  :: f
      intent(out) :: df
!
      character(len=2) :: id
!
!  Identify module and boundary conditions.
!
      if (nosupersat) then
        if (headtt.or.ldebug) print*,'not SOLVED: dssat_dt'
      else
        if (headtt.or.ldebug) print*,'SOLVE dssat_dt'
      endif
      if (headtt) then
        write(id,'(i0)')
        call identify_bcs('ssat'//trim(id),issat)
      endif
!
!  Passive scalar equation.
!
      df(l1:l2,m,n,issat)=df(l1:l2,m,n,issat)-p%ugssat
      df(l1:l2,m,n,ilnTT)=df(l1:l2,m,n,ilnTT)-p%uglnTT
      if (supersat_diff/=0.) &
          df(l1:l2,m,n,issat)=df(l1:l2,m,n,issat)+supersat_diff*p%del2ssat
!
      if (thermal_diff/=0.) &
          df(l1:l2,m,n,ilnTT)=df(l1:l2,m,n,ilnTT)+thermal_diff*p%del2lnTT
!
      ! 1-June-16/XY coded 
      if (lsupersat_sink) then
        if (Rsupersat_sink) then
          bump=A1*p%uu(:,3)
        elseif (lupdraft) then
          bump=A1*updraft
        else
          bump=A1*p%uu(:,3)-f(l1:l2,m,n,issat)*p%tausupersat
        endif
        df(l1:l2,m,n,issat)=df(l1:l2,m,n,issat)+bump
      endif
!
      if (ldustdensity.and.lcondensation_rate) then
!
!  compute sum of particle radii
!
        qv=f(l1:l2,m,n,issat)
        supersaturation=qv/vapor_mixing_ratio_qvs-1.
        radius_sum=0.
!       do k=1,ndustspec
!         radius_sum=radius_sum+p%ad(:,k)*p%nd(:,k)
!         print*,k,radius_sum(1:5)
!       enddo
        condensation_rate_Cd=4.*pi*supersaturation*p%condensationRate
        df(l1:l2,m,n,issat)=df(l1:l2,m,n,issat)-condensation_rate_Cd
        if (ltemperature) df(l1:l2,m,n,ilnTT)=df(l1:l2,m,n,ilnTT)+condensation_rate_Cd/(p%cp*p%TT)
      endif
!
! 17-10-18: Xiang-Yu coded. Solve supersaturation by solving equations for the temperature, mixing ratio
      
      if (lcondensation_rate) then
        df(l1:l2,m,n,issat)=df(l1:l2,m,n,issat)-p%condensationRate
        if (ltemperature) df(l1:l2,m,n,ilnTT)=df(l1:l2,m,n,ilnTT)+p%condensationRate*latent_heat/cp
!           print*,'T=',df(l1:l2,m,n,ilnTT)
        es_T=c1*exp(-c2/f(l1:l2,m,n,ilnTT))
        qvs_T=es_T/(Rv*rho0*f(l1:l2,m,n,ilnTT))
        supersaturation=f(l1:l2,m,n,issat)/qvs_T-1.
      endif
!
!  Diagnostics
!
      if (ldiagnos) then
        if (idiag_ssatrms/=0) call sum_mn_name(p%ssat**2,idiag_ssatrms,lsqrt=.true.)
        if (idiag_ssatmax/=0) call max_mn_name(p%ssat,idiag_ssatmax)
        if (idiag_ssatmin/=0) call max_mn_name(-p%ssat,idiag_ssatmin,lneg=.true.)
        if (idiag_uxssatm/=0) call sum_mn_name(p%uu(:,1)*p%ssat,idiag_uxssatm)
        if (idiag_uyssatm/=0) call sum_mn_name(p%uu(:,2)*p%ssat,idiag_uyssatm)
        if (idiag_uzssatm/=0) call sum_mn_name(p%uu(:,3)*p%ssat,idiag_uzssatm)
        if (idiag_tausupersatrms/=0) &
            call sum_mn_name(p%tausupersat**2,idiag_tausupersatrms,lsqrt=.true.)
        if (idiag_tausupersatmax/=0) call max_mn_name(p%tausupersat,idiag_tausupersatmax)
        if (idiag_tausupersatmin/=0) call max_mn_name(-p%tausupersat,idiag_tausupersatmin,lneg=.true.)
        if (idiag_condensationRaterms/=0) &
            call sum_mn_name(p%condensationRate**2,idiag_condensationRaterms,lsqrt=.true.)
        if (idiag_condensationRatemax/=0) call max_mn_name(p%condensationRate,idiag_condensationRatemax)
        if (idiag_condensationRatemin/=0) call max_mn_name(-p%condensationRate,idiag_condensationRatemin,lneg=.true.)
        if (idiag_temperaturerms/=0) &
            call sum_mn_name(p%lnTT**2,idiag_temperaturerms,lsqrt=.true.)
        if (idiag_temperaturemax/=0) call max_mn_name(p%lnTT,idiag_temperaturemax)
        if (idiag_temperaturemin/=0) call max_mn_name(-p%lnTT,idiag_temperaturemin,lneg=.true.)

        if (idiag_supersaturationrms/=0) &
            call sum_mn_name(supersaturation**2,idiag_temperaturerms,lsqrt=.true.)
        if (idiag_supersaturationmax/=0) call max_mn_name(supersaturation,idiag_supersaturationmax)
        if (idiag_supersaturationmin/=0) call max_mn_name(-supersaturation,idiag_supersaturationmin,lneg=.true.)
      endif
!
    endsubroutine dssat_dt
!***********************************************************************
    subroutine read_supersat_init_pars(iostat)
!
      use File_io, only: parallel_unit
!
      integer, intent(out) :: iostat
!
      read(parallel_unit, NML=supersat_init_pars, IOSTAT=iostat)
!
    endsubroutine read_supersat_init_pars
!***********************************************************************
    subroutine write_supersat_init_pars(unit)
!
      integer, intent(in) :: unit
!
      write(unit, NML=supersat_init_pars)
!
    endsubroutine write_supersat_init_pars
!***********************************************************************
    subroutine read_supersat_run_pars(iostat)
!
      use File_io, only: parallel_unit
!
      integer, intent(out) :: iostat
!
      read(parallel_unit, NML=supersat_run_pars, IOSTAT=iostat)
!
    endsubroutine read_supersat_run_pars
!***********************************************************************
    subroutine write_supersat_run_pars(unit)
!
      integer, intent(in) :: unit
!
      write(unit, NML=supersat_run_pars)
!
    endsubroutine write_supersat_run_pars
!
!***********************************************************************
    subroutine rprint_supersat(lreset,lwrite)
      use Diagnostics
!
      logical :: lreset
      logical, optional :: lwrite
!
      integer :: iname
      logical :: lwr
!
!
      lwr = .false.
      if (present(lwrite)) lwr=lwrite
!      
      if (lreset) then
        idiag_ssatrms=0; idiag_ssatmax=0; idiag_ssatmin=0
        idiag_uxssatm=0; idiag_uyssatm=0; idiag_uzssatm=0
        idiag_tausupersatrms=0; idiag_tausupersatmax=0; idiag_tausupersatmin=0
        idiag_condensationRaterms=0; idiag_condensationRatemax=0; idiag_condensationRatemin=0
        idiag_temperaturerms=0; idiag_temperaturemax=0; idiag_temperaturemin=0
        idiag_supersaturationrms=0; idiag_supersaturationmax=0; idiag_supersaturationmin=0

      endif
!
      do iname=1,nname
        call parse_name(iname,cname(iname),cform(iname),'ssatrms',idiag_ssatrms)
        call parse_name(iname,cname(iname),cform(iname),'ssatmax',idiag_ssatmax)
        call parse_name(iname,cname(iname),cform(iname),'ssatmin',idiag_ssatmin)
        call parse_name(iname,cname(iname),cform(iname),'uxssatm',idiag_uxssatm)
        call parse_name(iname,cname(iname),cform(iname),'uyssatm',idiag_uyssatm)
        call parse_name(iname,cname(iname),cform(iname),'uzssatm',idiag_uzssatm)
        call parse_name(iname,cname(iname),cform(iname),'tausupersatrms',idiag_tausupersatrms)
        call parse_name(iname,cname(iname),cform(iname),'tausupersatmax',idiag_tausupersatmax)
        call parse_name(iname,cname(iname),cform(iname),'tausupersatmin',idiag_tausupersatmin)
        call parse_name(iname,cname(iname),cform(iname),'condensationRaterms',idiag_condensationRaterms)
        call parse_name(iname,cname(iname),cform(iname),'condensationRatemax',idiag_condensationRatemax)
        call parse_name(iname,cname(iname),cform(iname),'condensationRatemin',idiag_condensationRatemin)
        call parse_name(iname,cname(iname),cform(iname),'temperaturerms',idiag_temperaturerms)
        call parse_name(iname,cname(iname),cform(iname),'temperaturemax',idiag_temperaturemax)
        call parse_name(iname,cname(iname),cform(iname),'temperaturemin',idiag_temperaturemin)

        call parse_name(iname,cname(iname),cform(iname),'supersaturationrms',idiag_supersaturationrms)
        call parse_name(iname,cname(iname),cform(iname),'supersaturationmax',idiag_supersaturationmax)
        call parse_name(iname,cname(iname),cform(iname),'supersaturationmin',idiag_supersaturationmin)

      enddo
!
      if (lwr) then 
        write(3,*) 'issat = ', issat
        write(3,*) 'itausupersat=', itausupersat
        write(3,*) 'icondensationRate=', icondensationRate
        write(3,*) 'ilnTT=', ilnTT
        write(3,*) 'isupersaturaitonrms=', idiag_supersaturationrms
      endif
!
    endsubroutine rprint_supersat 
!***********************************************************************
endmodule Supersat
