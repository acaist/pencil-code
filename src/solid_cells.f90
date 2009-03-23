! $Id$
!
!  This module add solid (as in no-fluid) cells in the domain.
!  This can be used e.g. in order to simulate a cylinder in a cross flow.
!
module Solid_Cells

  use Cparam
  use Cdata
  use Messages
  
  implicit none
  
  include 'solid_cells.h'

  integer, parameter           :: max_items=10
  integer                      :: ncylinders,nrectangles,dummy
  real, dimension(max_items,5) :: cylinder
  real, dimension(max_items,7) :: rectangle
  real, dimension(max_items)   :: cylinder_radius
  real, dimension(max_items)   :: cylinder_temp=703.0
  real, dimension(max_items) :: cylinder_xpos,cylinder_ypos,cylinder_zpos
  integer, dimension(mx,my,mz,4)  :: ba,ba_shift
  real :: skin_depth=0, init_uu=0, ampl_noise=0
  character (len=labellen), dimension(ninit) :: initsolid_cells='nothing'
  character (len=labellen) :: interpolation_method='staircase'
  integer, parameter :: iradius=1, ixpos=2,iypos=3,izpos=4,itemp=5
!
  namelist /solid_cells_init_pars/ &
       cylinder_temp, ncylinders, cylinder_radius, cylinder_xpos, &
       cylinder_ypos, cylinder_zpos, initsolid_cells, skin_depth, init_uu, &
       ampl_noise,interpolation_method
!
  namelist /solid_cells_run_pars/  &
       interpolation_method
!
  contains
!***********************************************************************
    subroutine initialize_solid_cells
!
!  Define the geometry of the solids.
!  There might be many separate solid objects of different geometries (currently
!  only cylinders are implemented however).
!
!  19-nov-2008/nils: coded
!
      integer :: icyl
!
      lsolid_cells=.true.
!
!  Define the geometry of the solid object.
!  For more complex geometries (i.e. for objects different than cylinders or
!  rectangles) this shold probably be included as a geometry.local file such that
!  one can define complex geometries on a case to case basis.
!  Alternatively one will here end up with a terribly long series
!  of case checks.
!
      do icyl=1,ncylinders
        if (cylinder_radius(icyl)>0) then
          cylinder(icyl,iradius)=cylinder_radius(icyl)
          cylinder(icyl,ixpos)=cylinder_xpos(icyl)
          cylinder(icyl,iypos)=cylinder_ypos(icyl)
          cylinder(icyl,izpos)=cylinder_zpos(icyl)
          cylinder(icyl,itemp)=cylinder_temp(icyl)
        else
          call fatal_error('initialize_solid_cells',&
               'All cylinders must have non-zero radii!')
        endif
      enddo
!
      call find_solid_cell_boundaries
      call calculate_shift_matrix
!
    endsubroutine initialize_solid_cells
!***********************************************************************
    subroutine init_solid_cells(f)
!
!  Initial conditions for cases where we have solid structures in the domain.
!  Typically the flow field is set such that we have no-slip conditions
!  at the solid structure surface.
! 
!  28-nov-2008/nils: coded
!
      use Cdata
      use Sub
      use Initcond

      real, dimension (mx,my,mz,mfarray) :: f

      intent(inout) :: f
      
      integer, pointer :: iglobal_cs2,iglobal_glnTT
      real :: a2,rr2,pphi,wall_smoothing,rr2_low,rr2_high,shiftx,shifty
      real :: wall_smoothing_temp,xr,yr
      integer i,j,k,cyl,jj,icyl


      do jj=1,ninit
      select case(initsolid_cells(jj))
!
!   This overrides any initial conditions set in the Hydro module.
!
      case('nothing')
        if (lroot) print*,'init_solid_cells: nothing'
      case('cylinderstream_x')
!   Stream functions for flow around a cylinder as initial condition. 
        call gaunoise(ampl_noise,f,iux,iuz)
        f(:,:,:,iux)=f(:,:,:,iux)+init_uu
        shiftx=0
        do i=l1,l2
        do j=m1,m2
        do k=n1,n2
!
!  Loop over all cylinders
!
          do icyl=1,ncylinders
            a2 = cylinder(icyl,1)**2
            xr=x(i)-cylinder(icyl,2)
            if (cylinder(icyl,3) .ne. 0) then
              print*,'When using cylinderstream_x all cylinders must have'
              print*,'zero offset in y-direction!'
              call fatal_error('init_solid_cells:','')
            endif
            yr=y(j)
            rr2 = xr**2+yr**2
            if (rr2 > a2) then
              do cyl=0,100
                if (cyl==0) then
                  wall_smoothing=1-exp(-(rr2-a2)/skin_depth**2)
                  f(i,j,k,iuy) = f(i,j,k,iuy)-init_uu*&
                       2*x(i)*y(j)*a2/rr2**2*wall_smoothing
                  f(i,j,k,iux) = f(i,j,k,iux)+init_uu*&
                       (0. - a2/rr2 + 2*y(j)**2*a2/rr2**2)&
                       *wall_smoothing
                  if (ilnTT .ne. 0) then
                    wall_smoothing_temp=1-exp(-(rr2-a2)/(sqrt(a2))**2)
                    f(i,j,k,ilnTT) = wall_smoothing_temp*f(i,j,k,ilnTT)&
                         +cylinder(icyl,5)*(1-wall_smoothing_temp)
                    f(i,j,k,ilnrho)=f(l2,m2,n2,ilnrho)&
                         *f(l2,m2,n2,ilnTT)/f(i,j,k,ilnTT)
                  endif
                else
                  shifty=cyl*Lxyz(2)
                  rr2_low =(x(i)+shiftx)**2+(y(j)+shifty)**2
                  rr2_high=(x(i)-shiftx)**2+(y(j)-shifty)**2
                  f(i,j,k,iux) = f(i,j,k,iux)+init_uu*( &
                       +2*(y(j)-shifty)**2*a2/rr2_high**2-a2/rr2_high&
                       +2*(y(j)+shifty)**2*a2/rr2_low**2 -a2/rr2_low)
                  f(i,j,k,iuy) = f(i,j,k,iuy)-init_uu*( &
                       +2*(x(i)-shiftx)*(y(j)-shifty)&
                       *a2/rr2_high**2&
                       +2*(x(i)+shiftx)*(y(j)+shifty)&
                       *a2/rr2_low**2)
                endif
              enddo
            else
              if (ilnTT .ne. 0) then
                f(i,j,k,ilnTT) = cylinder(icyl,5)
                f(i,j,k,ilnrho)=f(l2,m2,n2,ilnrho)&
                     *f(l2,m2,n2,ilnTT)/cylinder(icyl,5)
              endif
            end if
          end do
        end do
        end do
        enddo
      case('cylinderstream_y')
!   Stream functions for flow around a cylinder as initial condition.
        call gaunoise(ampl_noise,f,iux,iuz)
        f(:,:,:,iuy)=f(:,:,:,iuy)+init_uu
        shifty=0
        do i=l1,l2
        do j=m1,m2
        do k=n1,n2
          do icyl=1,ncylinders
            a2 = cylinder(icyl,1)**2
            yr=y(j)-cylinder(icyl,3)
            if (cylinder(icyl,2) .ne. 0) then
              print*,'When using cylinderstream_y all cylinders must have'
              print*,'zero offset in x-direction!'
              call fatal_error('init_solid_cells:','')
            endif
            xr=x(i)
            rr2 = xr**2+yr**2
            if (rr2 > a2) then
              do cyl=0,100
                if (cyl==0) then
                  wall_smoothing=1-exp(-(rr2-a2)/skin_depth**2)
                  f(i,j,k,iux) = f(i,j,k,iux)-init_uu*&
                       2*xr*yr*a2/rr2**2*wall_smoothing
                  f(i,j,k,iuy) = f(i,j,k,iuy)+init_uu*&
                       (0. - a2/rr2 + 2*xr**2*a2/rr2**2)&
                       *wall_smoothing
                  if (ilnTT .ne. 0) then
                    wall_smoothing_temp=1-exp(-(rr2-a2)/(sqrt(a2))**2)
                    f(i,j,k,ilnTT) = wall_smoothing_temp*f(i,j,k,ilnTT)&
                         +cylinder(icyl,5)*(1-wall_smoothing_temp)
                    f(i,j,k,ilnrho)=f(l2,m2,n2,ilnrho)&
                         *f(l2,m2,n2,ilnTT)/f(i,j,k,ilnTT)
                  endif
                else
                  shiftx=cyl*Lxyz(1)
                  rr2_low =(xr+shiftx)**2+(yr+shifty)**2
                  rr2_high=(xr-shiftx)**2+(yr-shifty)**2
                  f(i,j,k,iuy) = f(i,j,k,iuy)+init_uu*( &
                       +2*(xr-shiftx)**2*a2/rr2_high**2-a2/rr2_high&
                       +2*(xr+shiftx)**2*a2/rr2_low**2 -a2/rr2_low)
                  f(i,j,k,iux) = f(i,j,k,iux)-init_uu*( &
                       +2*(xr-shiftx)*(y(j)-shifty)&
                       *a2/rr2_high**2&
                       +2*(xr+shiftx)*(y(j)+shifty)&
                       *a2/rr2_low**2)
                endif
              enddo
            else
              if (ilnTT .ne. 0) then
                f(i,j,k,ilnTT) = cylinder(icyl,5)
                f(i,j,k,ilnrho)=f(l2,m2,n2,ilnrho)&
                     *f(l2,m2,n2,ilnTT)/cylinder(icyl,5)
              endif
            end if
          end do
        end do
        end do
        end do
f(:,m2-5:m2,:,iux)=0
      case default
        !
        !  Catch unknown values
        !
        if (lroot) print*,'No such value for init_solid_cells:',&
             trim(initsolid_cells(jj))
        call fatal_error('init_solid_cells','')
      endselect
    enddo
!
    endsubroutine init_solid_cells
!***********************************************************************  
    subroutine update_solid_cells(f)
!
!  Set the boundary values of the solid area such that we get a 
!  correct fluid-solid interface.
!
!  19-nov-2008/nils: coded
!
      real, dimension (mx,my,mz,mfarray) :: f
      integer :: i,j,k,idir,xind,yind,zind,icyl
      
      real :: y_cyl, x_cyl, r_cyl, r_new, r_point, sin_theta, cos_theta
      real :: xmirror, ymirror, phi
      integer :: lower_i, upper_i, lower_j, upper_j, ii, jj
      logical :: bax, bay
!
!  Find ghost points based on the mirror interpolation method
!
      if (interpolation_method=='mirror') then
        do i=l1,l2
        do j=m1,m2
        do k=n1,n2
          bax=(ba(i,j,k,1) .ne. 0) .and. (ba(i,j,k,1) .ne. 9)
          bay=(ba(i,j,k,2) .ne. 0) .and. (ba(i,j,k,2) .ne. 9)
!
!  Check if we are in a point which must be interpolated, i.e. we are inside
!  a solid geometry AND we are not more than three grid points from the 
!  closest solid-fluid interface
!
          if (bax.or.bay) then
!
!  Find x and y values of mirror point
!
            icyl=ba(i,j,k,4)
            x_cyl=cylinder(icyl,ixpos)
            y_cyl=cylinder(icyl,iypos)
            r_cyl=cylinder(icyl,iradius)
            r_point=sqrt(((x(i)-x_cyl)**2+(y(j)-y_cyl)**2))
            r_new=r_cyl+(r_cyl-r_point)
            sin_theta=(y(j)-y_cyl)/r_point
            cos_theta=(x(i)-x_cyl)/r_point
            xmirror=cos_theta*r_new+x_cyl
            ymirror=sin_theta*r_new+y_cyl
!
!  Check that we are indeed inside the solid geometry
!
            if (r_point>r_cyl) then
              call fatal_error('update_solid_cells:','r_point>r_cyl')
            endif
!
!  Find i and j indeces for points to be used during interpolation 
!
            do ii=1,mx
              if (x(ii)>xmirror) then
                lower_i=ii-1
                upper_i=ii
                exit
              endif
            enddo
!
            do jj=1,my
              if (y(jj)>ymirror) then
                lower_j=jj-1
                upper_j=jj
                exit
              endif
            enddo
!
!  First we use interpolations to find the value of the mirror point.
!  Then we use the interpolated value to find the value of the ghost point
!  by empoying either Dirichlet or Neuman boundary conditions.
!  Note that the currently implemented interpolation routine should be updated
!  for points close to the boundary where one of the corners are inside the
!  solid geometry.
!
              call interpolate_mirror_point(f,phi,iux,k,lower_i,upper_i,lower_j,&
                  upper_j,xmirror,ymirror)
              f(i,j,k,iux)=-phi
              call interpolate_mirror_point(f,phi,iuy,k,lower_i,upper_i,lower_j,&
                  upper_j,xmirror,ymirror)
              f(i,j,k,iuy)=-phi
              call interpolate_mirror_point(f,phi,iuz,k,lower_i,upper_i,lower_j,&
                  upper_j,xmirror,ymirror)
              f(i,j,k,iuz)=-phi
              if (ilnrho>0) then
                call interpolate_mirror_point(f,phi,ilnrho,k,lower_i,upper_i,&
                    lower_j,upper_j,xmirror,ymirror)
                f(i,j,k,ilnrho)=phi
              endif
              if (ilnTT>0) then
                call interpolate_mirror_point(f,phi,ilnTT,k,lower_i,upper_i,&
                    lower_j,upper_j,xmirror,ymirror)
                f(i,j,k,ilnTT)=2*cylinder_temp(icyl)-phi
              endif
          endif
        enddo
        enddo
        enddo
!
!  Find ghost points based on the staircase interpolation method
!
      elseif (interpolation_method=='staircase') then
        do i=l1,l2
        do j=m1,m2
        do k=n1,n2
          do idir=1,3
            if (ba_shift(i,j,k,idir).ne.0) then
              xind=i
              yind=j
              zind=k
              if (idir==1) then
                xind=i-ba_shift(i,j,k,idir)
              elseif (idir==2) then
                yind=j-ba_shift(i,j,k,idir)
              elseif (idir==3) then
                zind=k-ba_shift(i,j,k,idir)
              else
                print*,'No such idir!...exiting!'
                stop
              endif
!                
!  Only update the solid cell "ghost points" if all indeces are non-zero.
!  In this way we might loose the innermost "ghost point" if the processore
!  border is two grid cells inside the solid structure, but this will 
!  probably just have a very minor effect.
!
              if (xind.ne.0 .and. yind.ne.0 .and. zind.ne.0) then
                icyl=ba_shift(i,j,k,4)
                f(i,j,k,iux:iuz)=-f(xind,yind,zind,iux:iuz)
                if (ilnrho>0) f(i,j,k,ilnrho) = f(xind,yind,zind,ilnrho)
                if (ilnTT>0) f(i,j,k,ilnTT) = &
                    2*cylinder_temp(icyl)-f(xind,yind,zind,ilnTT)
              endif
            endif
          enddo
        enddo
        enddo
        enddo
      endif
!
    endsubroutine update_solid_cells
!***********************************************************************  
    subroutine interpolate_mirror_point(f,phi,ivar,k,lower_i,upper_i,lower_j,upper_j,xmirror,ymirror)
!
!  Interpolate value in i mirror point from the four corner values
!
!  23-dec-2008/nils: coded
!
      real, dimension (mx,my,mz,mfarray), intent(in) :: f
      integer :: lower_i,upper_i,lower_j,upper_j,k,ivar
      real :: xmirror,ymirror,phi, hx1, hy1,hy2,hx2
!
      hx1=xmirror-x(lower_i)
      hx2=x(upper_i)-xmirror
      hy1=ymirror-y(lower_j)
      hy2=y(upper_j)-ymirror
!
      phi=&
          (f(lower_i,upper_j,k,ivar)*hx2*hy1 &
          +f(upper_i,upper_j,k,ivar)*hx1*hy1 &
          +f(lower_i,lower_j,k,ivar)*hx2*hy2 &
          +f(upper_i,lower_j,k,ivar)*hx1*hy2)/((hx1+hx2)*(hy1+hy2))
!
    end subroutine interpolate_mirror_point
!***********************************************************************  
    function in_solid_cell(part_pos,part_rad)
!
!  Check if the position px,py,pz is within a colid cell
!
!  02-dec-2008/nils: coded
!
      logical :: in_solid_cell
      real, dimension(3) :: cyl_pos, part_pos
      real :: cyl_rad,distance2,part_rad
      integer :: icyl, i
!
      in_solid_cell=.false.
!
      do icyl=1,ncylinders
        cyl_rad=cylinder(icyl,1)
        cyl_pos=cylinder(icyl,2:4)
        distance2=0
        do i=1,3
          distance2=distance2+(cyl_pos(i)-part_pos(i))**2
        enddo
        if (sqrt(distance2)<cyl_rad+part_rad) then
          in_solid_cell=.true.
        endif
      enddo
!
    end function in_solid_cell
!***********************************************************************  
    subroutine freeze_solid_cells(df)
!
!  If we are in a solid cell set df=0 for all variables
!
!  19-nov-2008/nils: coded
!
      real, dimension (mx,my,mz,mvar) :: df
      integer :: i,j,k
! 
      do i=l1,l2
        if (&
             (ba(i,m,n,1).ne.0).or.&
             (ba(i,m,n,2).ne.0).or.&
             (ba(i,m,n,3).ne.0)) then
          df(i,m,n,:)=0
        endif
      enddo
!
    endsubroutine freeze_solid_cells
!***********************************************************************
    subroutine read_solid_cells_init_pars(unit,iostat)
      integer, intent(in) :: unit
      integer, intent(inout), optional :: iostat

      if (present(iostat)) then
        read(unit,NML=solid_cells_init_pars,ERR=99, IOSTAT=iostat)
      else
        read(unit,NML=solid_cells_init_pars,ERR=99)
      endif

99    return
    endsubroutine read_solid_cells_init_pars
!***********************************************************************
    subroutine read_solid_cells_run_pars(unit,iostat)
      integer, intent(in) :: unit
      integer, intent(inout), optional :: iostat

      if (present(iostat)) then
        read(unit,NML=solid_cells_run_pars,ERR=99, IOSTAT=iostat)
      else
        read(unit,NML=solid_cells_run_pars,ERR=99)
      endif

99    return
    endsubroutine read_solid_cells_run_pars
!***********************************************************************
    subroutine write_solid_cells_init_pars(unit)
      integer, intent(in) :: unit

      write(unit,NML=solid_cells_init_pars)

    endsubroutine write_solid_cells_init_pars
!***********************************************************************
    subroutine write_solid_cells_run_pars(unit)
      integer, intent(in) :: unit

      write(unit,NML=solid_cells_run_pars)

    endsubroutine write_solid_cells_run_pars
!***********************************************************************
    subroutine find_solid_cell_boundaries
!
!  Find the boundaries of the geometries such that we can set the
!  ghost points inside the solid geometry in order to achieve the
!  correct no-slip boundaries.
!  
!  Store data in the ba array.
!  If ba(ip,jp,kp,1)= 0 we are in a fluid cell (i.e. NOT inside a solid geometry)
!  If ba(ip,jp,kp,1)= 9 we are inside a solid geometry, but far from the boundary
!  If ba(ip,jp,kp,1)=-1 we are inside a solid geometry, and the point at ip+1
!                       is outside the geometry. 
!  If ba(ip,jp,kp,1)=-3 we are inside a solid geometry, and the point at ip+3
!                       is outside the geometry. 
!  If ba(ip,jp,kp,2)=-3 we are inside a solid geometry, and the point at jp+3
!                       is outside the geometry. 
!  The number stored in ba(ip,jp,kp,4) is the number of the cylinder
!
!  19-nov-2008/nils: coded
!
      integer :: i,j,k,icyl,cw
      real :: x2,y2,xval_p,xval_m,yval_p,yval_m
!
!  Initialize ba
!
      ba=0
!
!  Loop over all cylinders (this should actually be a loop over all
!  geometries!)
!
      do icyl=1,ncylinders
!
!  First we look in x-direction
!
        k=l1
        do j=m1,m2
!
!  Check if we are inside the cylinder for y(j) (i.e. if x2>0)
!
          x2=cylinder(icyl,1)**2-(y(j)-cylinder(icyl,3))**2
          if (x2>0) then
!
!  Find upper and lower x-values for the surface of the cylinder for y(j)
!
            xval_p=cylinder(icyl,2)+sqrt(x2)
            xval_m=cylinder(icyl,2)-sqrt(x2)            
            do i=l1,l2
              if (x(i)<xval_p .and. x(i)>xval_m) then
                !
                if (x(i+1)>xval_p) then
                  if (.not. ba_defined(i,j)) then
                    ba(i,j,:,1)=-1
                    ba(i,j,:,4)=icyl
                  else
                    call find_closest_wall(i,j,k,icyl,cw)
                    if (cw==1) ba(i,j,:,1)=-1
                  endif
                endif
                !
                if (x(i+2)>xval_p .and. x(i+1)<xval_p) then
                  if (.not. ba_defined(i,j)) then
                    ba(i,j,:,1)=-2
                    ba(i,j,:,4)=icyl
                  else
                    call find_closest_wall(i,j,k,icyl,cw)
                    if (cw==1) ba(i,j,:,1)=-2
                  endif
                endif
                !
                if (x(i+3)>xval_p .and. x(i+2)<xval_p) then
                  if (.not. ba_defined(i,j)) then
                    ba(i,j,:,1)=-3
                    ba(i,j,:,4)=icyl
                  else
                    call find_closest_wall(i,j,k,icyl,cw)
                    if (cw==1) ba(i,j,:,1)=-3
                  endif
                endif
                !
                if (x(i-1)<xval_m) then
                  if (.not. ba_defined(i,j)) then
                    ba(i,j,:,1)=1
                    ba(i,j,:,4)=icyl
                  else
                    call find_closest_wall(i,j,k,icyl,cw)
                    if (cw==-1) ba(i,j,:,1)=1
                  endif
                endif
                !
                if (x(i-2)<xval_m .and. x(i-1)>xval_m) then
                  if (.not. ba_defined(i,j)) then
                    ba(i,j,:,1)=2
                    ba(i,j,:,4)=icyl
                  else
                    call find_closest_wall(i,j,k,icyl,cw)
                    if (cw==-1) ba(i,j,:,1)=2
                  endif
                endif
                !
                if (x(i-3)<xval_m .and. x(i-2)>xval_m) then
                  if (.not. ba_defined(i,j)) then
                    ba(i,j,:,1)=3
                    ba(i,j,:,4)=icyl
                  else
                    call find_closest_wall(i,j,k,icyl,cw)
                    if (cw==-1) ba(i,j,:,1)=3
                  endif
                endif
                !
                if (ba(i,j,k,1)==0) then
                  ba(i,j,:,1)=9
                  ba(i,j,:,4)=icyl
                endif
                !
              endif
            enddo
          endif
        enddo
!
!  Then we look in y-direction
!
        do i=l1,l2
!
!  Check if we are inside the cylinder for x(i) (i.e. if y2>0)
!
          y2=cylinder(icyl,1)**2-(x(i)-cylinder(icyl,2))**2
          if (y2>0) then
!
!  Find upper and lower y-values for the surface of the cylinder for x(i)
!
            yval_p=cylinder(icyl,3)+sqrt(y2)
            yval_m=cylinder(icyl,3)-sqrt(y2)            
            do j=m1,m2
              if (y(j)<yval_p .and. y(j)>yval_m) then
                if (y(j+1)>yval_p) then
                  if (.not. ba_defined(i,j)) then
                    ba(i,j,:,2)=-1
                    ba(i,j,:,4)=icyl
                  else
                    call find_closest_wall(i,j,k,icyl,cw)
                    if (cw==2) ba(i,j,:,2)=-1                  
                  endif
                endif
!
                if (y(j+2)>yval_p .and. y(j+1)<yval_p) then
                  if (.not. ba_defined(i,j)) then
                    ba(i,j,:,2)=-2
                    ba(i,j,:,4)=icyl
                  else
                    call find_closest_wall(i,j,k,icyl,cw)
                    if (cw==2) ba(i,j,:,2)=-2                  
                  endif
                endif
!
                if (y(j+3)>yval_p .and. y(j+2)<yval_p) then
                  if (.not. ba_defined(i,j)) then
                    ba(i,j,:,2)=-3
                    ba(i,j,:,4)=icyl
                  else
                    call find_closest_wall(i,j,k,icyl,cw)
                    if (cw==2) ba(i,j,:,2)=-3                  
                  endif
                endif
!
                if (y(j-1)<yval_m) then
                  if (.not. ba_defined(i,j)) then
                    ba(i,j,:,2)=1
                    ba(i,j,:,4)=icyl
                  else
                    call find_closest_wall(i,j,k,icyl,cw)
                    if (cw==-2) ba(i,j,:,2)=1                  
                  endif
                endif
!
                if (y(j-2)<yval_m .and. y(j-1)>yval_m) then
                  if (.not. ba_defined(i,j)) then
                    ba(i,j,:,2)=2
                    ba(i,j,:,4)=icyl
                  else
                    call find_closest_wall(i,j,k,icyl,cw)
                    if (cw==-2) ba(i,j,:,2)=2                  
                  endif
                endif
!
                if (y(j-3)<yval_m .and. y(j-2)>yval_m) then
                  if (.not. ba_defined(i,j)) then
                    ba(i,j,:,2)=3
                    ba(i,j,:,4)=icyl
                  else
                    call find_closest_wall(i,j,k,icyl,cw)
                    if (cw==-2) ba(i,j,:,2)=3                  
                  endif
                endif
!
                if (ba(i,j,k,2)==0) then
                  ba(i,j,:,2)=9
                  ba(i,j,:,4)=icyl
                endif
              endif
            enddo
          endif
        enddo
      enddo
!
    endsubroutine find_solid_cell_boundaries
!***********************************************************************
    subroutine calculate_shift_matrix
!
!  Set up the shift matrix
!
!  19-nov-2008/nils: coded
!
      integer :: i,j,k,idir
      integer :: sgn
!
      ba_shift=0
!
      do i=l1,l2
      do j=m1,m2
      do k=n1,n2
        do idir=1,3
!
!  If ba is non-zero find the shift matrix
!
          if (ba(i,j,k,idir).ne.0 .and. ba(i,j,k,idir).ne.9) then
            sgn=-ba(i,j,k,idir)/abs(ba(i,j,k,idir))
            ba_shift(i,j,k,idir)=2*ba(i,j,k,idir)+sgn
            ba_shift(i,j,k,4)=ba(i,j,k,4)
          endif
        enddo
      enddo
      enddo
      enddo
!
    endsubroutine calculate_shift_matrix
!***********************************************************************  
    subroutine find_closest_wall(i,j,k,icyl,cw)
!
!  Find the direction of the closest wall for given grid point and cylinder
!
!  28-nov-2008/nils: coded
!
      integer :: i,j,k,cw,icyl
      real :: xval_p,xval_m,yval_p,yval_m,maxval,x2,y2,minval,dist
!
      x2=cylinder(icyl,1)**2-(y(j)-cylinder(icyl,3))**2
      y2=cylinder(icyl,1)**2-(x(i)-cylinder(icyl,2))**2
      xval_p=cylinder(icyl,2)+sqrt(x2)
      xval_m=cylinder(icyl,2)-sqrt(x2)            
      yval_p=cylinder(icyl,3)+sqrt(y2)
      yval_m=cylinder(icyl,3)-sqrt(y2)            
!
      minval=impossible
      cw=0
!
      dist=xval_p-x(i)
      if (dist<minval) then
        minval=dist
        cw=1
      endif
!
      dist=yval_p-y(j)
      if (dist<minval) then
        minval=dist
        cw=2
      endif
!
      dist=x(i)-xval_m
      if (dist<minval) then
        minval=dist
        cw=-1
      endif
!
      dist=y(j)-yval_m
      if (dist<minval) then
        minval=dist
        cw=-2
      endif
!
    end subroutine find_closest_wall
!***********************************************************************  
    function ba_defined(i,j)
!
!  28-nov-2008/nils: coded
!
!  Check if ba for the point of interest has been defined for another direction.
!  This is only interesting if interpolation_method=='staircase',
!  otherwise this function always return .false.
!
      integer :: i,j,k
      logical :: lba1=.true.,lba2=.true.
      logical :: ba_defined
!
      k=3
!
      if (interpolation_method=='staircase') then
        if (ba(i,j,k,1)==0 .or. ba(i,j,k,1)==9) then
          lba1=.false.
        endif
!
        if (ba(i,j,k,2)==0 .or. ba(i,j,k,2)==9) then
          lba2=.false.
        endif
!
        if (lba1 .or. lba2) then
          ba_defined=.true.
        else
          ba_defined=.false.
        endif
      else
        ba_defined=.false.
      endif
!
    end function ba_defined
!***********************************************************************  
    subroutine close_interpolation(f,ix0,iy0,iz0,ivar1,ivar2,xxp,gp)
!
!  20-mar-2009/nils: coded
!
! This routine check if any of the corners in the interpolation cell
! are inside a solid geometry. If they are some special treatment is
! required.
! 
! WARNING: This routine only works for cylinders with an infinitely long
! WARNING: central axis in the z-direction!
!
! The particle is located at point p at the coordinates [xp,yp].
! A normal to the cylinder surface from point s with coordinates [xs,ys] 
! pass thourgh p.
!
! If a one of the corner points of the grid cell is within a solid geometry
! the normal passing through both s and p are continued outward until a
! grid line is reached. If this line has constant, say y, then the variables
! constdir and vardir are given the values 2 and 1, respectively.  
!
      real, dimension (mx,my,mz,mfarray), intent(in) :: f
      integer, intent(in) :: ix0,iy0,iz0,ivar1,ivar2
      real, dimension (ivar2-ivar1+1), intent(inout) :: gp
      real :: x0,y0,z0,rs,verylarge=1e9,varval,rint1,rint2,fint,rps,rintp
      integer :: index,ix1,iy1,iz1,min
      real, dimension(3), intent(in) :: xxp
      real, dimension(2,2) :: rij
      real, dimension(3,2) :: bordervalue
      integer, dimension(3,2) :: borderindex
      integer, dimension(4) :: constdir_arr, vardir_arr, topbot_arr
      real, dimension(2) :: xyint, p_cylinder
      real :: xtemp,r,xp,yp,R1,Rsmall,xs,ys,rp,dist,yp_cylinder,xp_cylinder
      integer :: constdir,vardir,topbot_tmp,dirconst,dirvar,icyl,counter,topbot
      real :: x1,x2,f1,f2,rij_min,rij_max,inputvalue
!
! Define some help variables
!
      ix1=ix0+1
      iy1=iy0+1
      iz1=iz0+1
      bordervalue(1,1)=x(ix0)
      bordervalue(2,1)=y(iy0)
      bordervalue(1,2)=x(ix1)
      bordervalue(2,2)=y(iy1)
      borderindex(1,1)=ix0
      borderindex(2,1)=iy0
      borderindex(1,2)=ix1
      borderindex(2,2)=iy1
      constdir_arr=(/2,2,1,1/)
      vardir_arr=(/1,1,2,2/)
      topbot_arr=(/2,1,2,1/)
!
! Loop over all cylinders to check for particles in partially solid cells
!
      do icyl=1,ncylinders
        x0=cylinder(icyl,ixpos)
        y0=cylinder(icyl,iypos)
        z0=cylinder(icyl,izpos)
        rs=cylinder(icyl,iradius)
        xp=xxp(1)
        yp=xxp(2)
!
! Check if the four neighboring points are outside the cylinder or not
!
        rij(1,1)=sqrt((x(ix0)-x0)**2+(y(iy0)-y0)**2)
        rij(1,2)=sqrt((x(ix0)-x0)**2+(y(iy1)-y0)**2)
        rij(2,1)=sqrt((x(ix1)-x0)**2+(y(iy0)-y0)**2)
        rij(2,2)=sqrt((x(ix1)-x0)**2+(y(iy1)-y0)**2)            
        if (minval(rij) < rs) then
          R1=verylarge
          Rsmall=verylarge/2.0
!
! Determine the point s on the cylinder surface where the normal to the
! cylinder surface pass through the point p. 
!
          xs=rs/rp*xp
          ys=rs/rp*yp
!
! Find distance from point p to point s
!
          dist=(xp-xs)**2+(yp-ys)**2
!
! Find the x and y coordinates of p in a coordiante system with origin
! in the center of the cylinder
!
          yp_cylinder=yp-y0
          xp_cylinder=xp-x0
          p_cylinder(1)=xp_cylinder
          p_cylinder(2)=yp_cylinder
          rp=sqrt(xp_cylinder**2+yp_cylinder**2)
!
! Find which grid line is the closest one in the direction
! away from the cylinder surface
!
! Check the distance etc. to all the four (in 2D) possible 
! grid lines. Pick the grid line which the normal to the
! cylinder surface (which also pass through the point [xp,yp])
! cross first. This grid line should however
! be OUTSIDE the point [xp,yp] compared to the cylinder surface.
!
          do counter=1,4
            constdir=constdir_arr(counter)
            vardir=vardir_arr(counter)
            topbot_tmp=topbot_arr(counter)
!
! Find the position, xtemp, in the variable direction
! where the normal cross the grid line
!
            xtemp=(p_cylinder(vardir)/(p_cylinder(constdir)+tini))*(bordervalue(constdir,topbot_tmp)-cylinder(icyl,constdir+1))
!
! Find the distance, r, from the center of the cylinder
! to the point where the normal cross the grid line
!
            if (abs(xtemp) > verylarge) then
              r=verylarge*2
            else
              r=sqrt(xtemp**2+(bordervalue(constdir,topbot_tmp)-cylinder(icyl,constdir+1))**2)
            endif
  !
  ! Check if the point xtemp is outside the cylinder,
  ! outside the point [xp,yp] and that it cross the grid
  ! line within this grid cell
  !
            if ((r > rs) .and. (r > rp) &
                .and.(xtemp+cylinder(icyl,vardir+1) > bordervalue(vardir,1))&
                .and.(xtemp+cylinder(icyl,vardir+1) < bordervalue(vardir,2)))then
              R1=r
            else
              R1=verylarge
            endif
  !
  ! If we have a new all time low (in radius) go on....
  !
            if (R1 < Rsmall) then
              Rsmall=R1                
              xyint(vardir)=xtemp+cylinder(icyl,vardir+1)
              xyint(constdir)=bordervalue(constdir,topbot_tmp)
              dirconst=constdir
              dirvar=vardir
              topbot=topbot_tmp
              if (constdir == 2) then
                rij_min=rij(1,topbot_tmp)
                rij_max=rij(2,topbot_tmp)
              else
                rij_min=rij(topbot_tmp,1)
                rij_max=rij(topbot_tmp,2)
              endif
              inputvalue=bordervalue(constdir,topbot_tmp)-cylinder(icyl,constdir+1)
            endif
          end do
!
! Loop over all indeces
!
          do index=ivar1,ivar2
!
! Check if the endpoints in the variable direction are
! outside the cylinder. If they are not define the endpoints
! as where the grid line cross the cylinder surface.
! Find the variable value at the endpoints.
!
            min=1
            if (dirconst == 2) then
              varval=f(borderindex(dirvar,1),borderindex(dirconst,topbot),iz0,index)
            else
              varval=f(borderindex(dirconst,topbot),borderindex(dirvar,1),iz0,index)
            endif

            call find_point(rij_min,rs,varval,inputvalue,x1,bordervalue(dirvar,1),bordervalue(dirvar,2),min,f1,cylinder(icyl,dirvar+1))
            min=0
            if (dirconst == 2) then
              varval=f(borderindex(dirvar,2),borderindex(dirconst,topbot),iz0,index)
            else
              varval=f(borderindex(dirconst,topbot),borderindex(dirvar,2),iz0,index)
            endif
            call find_point(rij_max,rs,varval,inputvalue,x2,bordervalue(dirvar,1),bordervalue(dirvar,2),min,f2,cylinder(icyl,dirvar+1))
!
! Find the interpolation values between the two endpoints of
! the line and the normal from the cylinder.
!
            rint1=xyint(dirvar)-x1
            rint2=x2-xyint(dirvar)
!
! Find the interpolated value on the line
!
            fint=(rint1*f2+rint2*f1)/(x2-x1)
!
! Find the weigthing factors for the point on the line
! and the point on the cylinder surface.
!
            rps=rp-rs
            rintp=Rsmall-rp
!
! Perform the final interpolation
!
            gp(index)=(rps*fint+rintp*0)/(Rsmall-rs)
          enddo
        endif
      enddo
      !
    end subroutine close_interpolation
!***********************************************************************  
    subroutine find_point(rij,rs,f,yin,xout,xmin,xmax,min,fout,x0)
!
! 20-mar-2009/nils: coded
!
! Check if a grid line has any of it ends inside a solid cell - if so
! find the point where the grid line enters the solid cell.
!
      integer, intent(in) :: min
      real, intent(in) :: xmin,xmax,rij,rs,f,yin,x0
      real, intent(out) :: fout,xout
      real :: xvar,xout0
!
      if (min == 1) then
        xvar=xmin
      else
        xvar=xmax
      endif
!
      if (rij > rs) then
        xout=xvar
        fout=f
      else
        xout0=sqrt(rs**2-yin**2)
        xout=xout0+x0
        if ((xout > xmax) .or. (xout < xmin)) then
          xout=x0-xout0
        endif
        fout=0
      endif
!
    end subroutine find_point
!***********************************************************************  
  endmodule Solid_Cells
