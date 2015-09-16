# field_skeleton.py
# Written by Simon Candelaresi (iomsn1@gmail.com)

"""
Finds the structure of the field's skeleton, i.e. null points, separatrix
layers and separators using the trilinear method by
Haynes-Parnell-2007-14-8-PhysPlasm (http://dx.doi.org/10.1063/1.2756751) and
Haynes-Parnell-2010-17-9-PhysPlasm (http://dx.doi.org/10.1063/1.3467499).
"""

import numpy as np
import os as os
from pencilnew.math.interpolation import vec_int
try:
    import vtk as vtk
except:
    print("Warning: no vtk library found.")
try:
    import h5py as h5py
except:
    print("Warning: no h5py library found.")


class NullPoint(object):
    """
    Contains the position of the null points.
    """

    def __init__(self):
        """
        Fill members with default values.
        """

        self.nulls = []

    def find_nullpoints(self, var, field):
        """
        Find the null points to the field 'field' with information from 'var'.

        call signature:

            find_nullpoints(var, field)

        Arguments:

        *var*:
            The var object from the read_var routine.

        *field*:
            The vector field.
        """

        def __triLinear_interpolation(x, y, z, coefTri):
            """ Compute the interpolated field at (normalized) x, y, z. """
            return coefTri[0] + coefTri[1]*x + coefTri[2]*y + coefTri[3]*x*y +\
                   coefTri[4]*z + coefTri[5]*x*z + coefTri[6]*y*z + \
                   coefTri[7]*x*y*z

        def __grad_field_1(x, y, z, coefTri, dd):
            """ Compute the inverse of the gradient of the field. """
            gf1 = np.zeros((3, 3))
            gf1[0, :] = (__triLinear_interpolation(x+dd, y, z, coefTri) - \
                         __triLinear_interpolation(x-dd, y, z, coefTri))/(2*dd)
            gf1[1, :] = (__triLinear_interpolation(x, y+dd, z, coefTri) - \
                         __triLinear_interpolation(x, y-dd, z, coefTri))/(2*dd)
            gf1[2, :] = (__triLinear_interpolation(x, y, z+dd, coefTri) - \
                         __triLinear_interpolation(x, y, z-dd, coefTri))/(2*dd)
            # Invert the matrix.
            if np.linalg.det(gf1) != 0 and not np.max(np.isnan(gf1)):
                gf1 = np.matrix(gf1).I
            else:
                gf1 *= 0
            return gf1

        def __newton_raphson(xyz0, coefTri):
            """ Newton-Raphson method for finding null-points. """
            xyz = np.array(xyz0)
            iterMax = 10
            dd = 1e-4
            tol = 1e-5

            for i in range(iterMax):
                diff = __triLinear_interpolation(xyz[0], xyz[1],
                                                 xyz[2], coefTri) * \
                       __grad_field_1(xyz[0], xyz[1], xyz[2], coefTri, dd)
                diff = np.array(diff)[0]
                xyz = xyz - diff
                if any(abs(diff) < tol) or any(abs(diff) > 1):
                    return xyz

            return np.array(xyz)

        # 1) Reduction step.
        # Find all cells for which all three field components change sign.
        sign_field = np.sign(field)
        reduced_cells = True
        for comp in range(3):
            reduced_cells *= \
            ((sign_field[comp, 1:, 1:, 1:]*sign_field[comp, :-1, 1:, 1:] < 0) + \
            (sign_field[comp, 1:, 1:, 1:]*sign_field[comp, 1:, :-1, 1:] < 0) + \
            (sign_field[comp, 1:, 1:, 1:]*sign_field[comp, 1:, 1:, :-1] < 0) + \
            (sign_field[comp, 1:, 1:, 1:]*sign_field[comp, :-1, :-1, 1:] < 0) + \
            (sign_field[comp, 1:, 1:, 1:]*sign_field[comp, 1:, :-1, :-1] < 0) + \
            (sign_field[comp, 1:, 1:, 1:]*sign_field[comp, :-1, 1:, :-1] < 0) + \
            (sign_field[comp, 1:, 1:, 1:]*sign_field[comp, :-1, :-1, :-1] < 0))

        # Find null points in these cells.
        self.nulls = []
        for cell_idx in range(np.sum(reduced_cells)):
            # 2) Analysis step.

            # Find the indices of the cell where to look for the null point.
            idx_x = np.where(reduced_cells == True)[2][cell_idx]
            idx_y = np.where(reduced_cells == True)[1][cell_idx]
            idx_z = np.where(reduced_cells == True)[0][cell_idx]
            x = var.x
            y = var.y
            z = var.z

            # Compute the coefficients for the trilinear interpolation.
            coefTri = np.zeros((8, 3))
            coefTri[0] = field[:, idx_z, idx_y, idx_x]
            coefTri[1] = field[:, idx_z, idx_y, idx_x+1] - \
                         field[:, idx_z, idx_y, idx_x]
            coefTri[2] = field[:, idx_z, idx_y+1, idx_x] - \
                         field[:, idx_z, idx_y, idx_x]
            coefTri[3] = field[:, idx_z, idx_y+1, idx_x+1] - \
                         field[:, idx_z, idx_y, idx_x+1] - \
                         field[:, idx_z, idx_y+1, idx_x] + \
                         field[:, idx_z, idx_y, idx_x]
            coefTri[4] = field[:, idx_z+1, idx_y, idx_x] - \
                         field[:, idx_z, idx_y, idx_x]
            coefTri[5] = field[:, idx_z+1, idx_y, idx_x+1] - \
                         field[:, idx_z, idx_y, idx_x+1] - \
                         field[:, idx_z+1, idx_y, idx_x] + \
                         field[:, idx_z, idx_y, idx_x]
            coefTri[6] = field[:, idx_z+1, idx_y+1, idx_x] - \
                         field[:, idx_z, idx_y+1, idx_x] - \
                         field[:, idx_z+1, idx_y, idx_x] + \
                         field[:, idx_z, idx_y, idx_x]
            coefTri[7] = field[:, idx_z+1, idx_y+1, idx_x+1] - \
                         field[:, idx_z, idx_y+1, idx_x+1] - \
                         field[:, idx_z+1, idx_y, idx_x+1] - \
                         field[:, idx_z+1, idx_y+1, idx_x] + \
                         field[:, idx_z, idx_y, idx_x+1] + \
                         field[:, idx_z, idx_y+1, idx_x] + \
                         field[:, idx_z+1, idx_y, idx_x] - \
                         field[:, idx_z, idx_y, idx_x]

            # Contains the nulls obtained from each face.
            null_cell = []

            # Find the intersection of the curves field_i = field_j = 0.
            # The units are first normalized to the unit cube from 000 to 111.

            # face 1
            intersection = False
            coefBi = np.zeros((4, 3))
            coefBi[0] = coefTri[0] + coefTri[4]*0
            coefBi[1] = coefTri[1] + coefTri[5]*0
            coefBi[2] = coefTri[2] + coefTri[6]*0
            coefBi[3] = coefTri[3] + coefTri[7]*0
            # Find the roots for x0 and y0.
            polynomial = np.array([coefBi[1, 0]*coefBi[3, 1] -
                                   coefBi[1, 1]*coefBi[3, 0],
                                   coefBi[0, 0]*coefBi[3, 1] +
                                   coefBi[1, 0]*coefBi[2, 1] -
                                   coefBi[0, 1]*coefBi[3, 0] -
                                   coefBi[2, 0]*coefBi[1, 1],
                                   coefBi[0, 0]*coefBi[2, 1] -
                                   coefBi[0, 1]*coefBi[2, 0]])
            roots_x = np.roots(polynomial)
            if len(roots_x) == 0:
                roots_x = -np.ones(2)
            if len(roots_x) == 1:
                roots_x = np.array([roots_x, roots_x])
            roots_y = -(coefBi[0, 0]+coefBi[1, 0]*roots_x)/ \
                       (coefBi[2, 0]+coefBi[3, 0]*roots_x)
            if np.real(roots_x[0]) >= 0 and np.real(roots_x[0]) <= 1 and \
            np.real(roots_y[0]) >= 0 and np.real(roots_y[0]) <= 1:
                intersection = True
                root_idx = 0
            if np.real(roots_x[1]) >= 0 and np.real(roots_x[1]) <= 1 and \
            np.real(roots_y[1]) >= 0 and np.real(roots_y[1]) <= 1:
                intersection = True
                root_idx = 1
            if intersection:
                xyz0 = [roots_x[root_idx], roots_y[root_idx], 0]
                xyz = np.real(__newton_raphson(xyz0, coefTri))
                # Check if the null point lies inside the cell.
                if np.all(xyz >= 0) and np.all(xyz <= 1):
                    null_cell.append([xyz[0]*var.dx + x[idx_x],
                                      xyz[1]*var.dy + y[idx_y],
                                      xyz[2]*var.dz + z[idx_z]])

            # face 2
            intersection = False
            coefBi = np.zeros((4, 3))
            coefBi[0] = coefTri[0] + coefTri[4]*1
            coefBi[1] = coefTri[1] + coefTri[5]*1
            coefBi[2] = coefTri[2] + coefTri[6]*1
            coefBi[3] = coefTri[3] + coefTri[7]*1
            # Find the roots for x0 and y0.
            polynomial = np.array([coefBi[1, 0]*coefBi[3, 1] -
                                   coefBi[1, 1]*coefBi[3, 0],
                                   coefBi[0, 0]*coefBi[3, 1] +
                                   coefBi[1, 0]*coefBi[2, 1] -
                                   coefBi[0, 1]*coefBi[3, 0] -
                                   coefBi[2, 0]*coefBi[1, 1],
                                   coefBi[0, 0]*coefBi[2, 1] -
                                   coefBi[0, 1]*coefBi[2, 0]])
            roots_x = np.roots(polynomial)
            if len(roots_x) == 0:
                roots_x = -np.ones(2)
            if len(roots_x) == 1:
                roots_x = np.array([roots_x, roots_x])
            roots_y = -(coefBi[0, 0]+coefBi[1, 0]*roots_x)/ \
                       (coefBi[2, 0]+coefBi[3, 0]*roots_x)
            if np.real(roots_x[0]) >= 0 and np.real(roots_x[0]) <= 1 and \
            np.real(roots_y[0]) >= 0 and np.real(roots_y[0]) <= 1:
                intersection = True
                root_idx = 0
            if np.real(roots_x[1]) >= 0 and np.real(roots_x[1]) <= 1 and \
            np.real(roots_y[1]) >= 0 and np.real(roots_y[1]) <= 1:
                intersection = True
                root_idx = 1
            if intersection:
                xyz0 = [roots_x[root_idx], roots_y[root_idx], 1]
                xyz = np.real(__newton_raphson(xyz0, coefTri))
                # Check if the null point lies inside the cell.
                if np.all(xyz >= 0) and np.all(xyz <= 1):
                    null_cell.append([xyz[0]*var.dx + x[idx_x],
                                      xyz[1]*var.dy + y[idx_y],
                                      xyz[2]*var.dz + z[idx_z]])

            # face 3
            intersection = False
            coefBi = np.zeros((4, 3))
            coefBi[0] = coefTri[0] + coefTri[2]*0
            coefBi[1] = coefTri[1] + coefTri[3]*0
            coefBi[2] = coefTri[4] + coefTri[6]*0
            coefBi[3] = coefTri[5] + coefTri[7]*0
            # Find the roots for x0 and z0.
            polynomial = np.array([coefBi[1, 0]*coefBi[3, 2] -
                                   coefBi[1, 2]*coefBi[3, 0],
                                   coefBi[0, 0]*coefBi[3, 2] +
                                   coefBi[1, 0]*coefBi[2, 2] -
                                   coefBi[0, 2]*coefBi[3, 0] -
                                   coefBi[2, 0]*coefBi[1, 2],
                                   coefBi[0, 0]*coefBi[2, 2] -
                                   coefBi[0, 2]*coefBi[2, 0]])
            roots_x = np.roots(polynomial)
            if len(roots_x) == 0:
                roots_x = -np.ones(2)
            if len(roots_x) == 1:
                roots_x = np.array([roots_x, roots_x])
            roots_z = -(coefBi[0, 0]+coefBi[1, 0]*roots_x)/ \
                       (coefBi[2, 0]+coefBi[3, 0]*roots_x)
            if np.real(roots_x[0]) >= 0 and np.real(roots_x[0]) <= 1 and \
            np.real(roots_z[0]) >= 0 and np.real(roots_z[0]) <= 1:
                intersection = True
                root_idx = 0
            if np.real(roots_x[1]) >= 0 and np.real(roots_x[1]) <= 1 and \
            np.real(roots_z[1]) >= 0 and np.real(roots_z[1]) <= 1:
                intersection = True
                root_idx = 1
            if intersection:
                xyz0 = [roots_x[root_idx], 0, roots_z[root_idx]]
                xyz = np.real(__newton_raphson(xyz0, coefTri))
                # Check if the null point lies inside the cell.
                if np.all(xyz >= 0) and np.all(xyz <= 1):
                    null_cell.append([xyz[0]*var.dx + x[idx_x],
                                      xyz[1]*var.dy + y[idx_y],
                                      xyz[2]*var.dz + z[idx_z]])

            # face 4
            intersection = False
            coefBi = np.zeros((4, 3))
            coefBi[0] = coefTri[0] + coefTri[2]*1
            coefBi[1] = coefTri[1] + coefTri[3]*1
            coefBi[2] = coefTri[4] + coefTri[6]*1
            coefBi[3] = coefTri[5] + coefTri[7]*1
            # Find the roots for x0 and z0.
            polynomial = np.array([coefBi[1, 0]*coefBi[3, 2] -
                                   coefBi[1, 2]*coefBi[3, 0],
                                   coefBi[0, 0]*coefBi[3, 2] +
                                   coefBi[1, 0]*coefBi[2, 2] -
                                   coefBi[0, 2]*coefBi[3, 0] -
                                   coefBi[2, 0]*coefBi[1, 2],
                                   coefBi[0, 0]*coefBi[2, 2] -
                                   coefBi[0, 2]*coefBi[2, 0]])
            roots_x = np.roots(polynomial)
            if len(roots_x) == 0:
                roots_x = -np.ones(2)
            if len(roots_x) == 1:
                roots_x = np.array([roots_x, roots_x])
            roots_z = -(coefBi[0, 0]+coefBi[1, 0]*roots_x)/ \
                       (coefBi[2, 0]+coefBi[3, 0]*roots_x)
            if np.real(roots_x[0]) >= 0 and np.real(roots_x[0]) <= 1 and \
            np.real(roots_z[0]) >= 0 and np.real(roots_z[0]) <= 1:
                intersection = True
                root_idx = 0
            if np.real(roots_x[1]) >= 0 and np.real(roots_x[1]) <= 1 and \
            np.real(roots_z[1]) >= 0 and np.real(roots_z[1]) <= 1:
                intersection = True
                root_idx = 1
            if intersection:
                xyz0 = [roots_x[root_idx], 1, roots_z[root_idx]]
                xyz = np.real(__newton_raphson(xyz0, coefTri))
                # Check if the null point lies inside the cell.
                if np.all(xyz >= 0) and np.all(xyz <= 1):
                    null_cell.append([xyz[0]*var.dx + x[idx_x],
                                      xyz[1]*var.dy + y[idx_y],
                                      xyz[2]*var.dz + z[idx_z]])

            # face 5
            intersection = False
            coefBi = np.zeros((4, 3))
            coefBi[0] = coefTri[0] + coefTri[1]*0
            coefBi[1] = coefTri[2] + coefTri[3]*0
            coefBi[2] = coefTri[4] + coefTri[5]*0
            coefBi[3] = coefTri[6] + coefTri[7]*0
            # Find the roots for y0 and z0.
            polynomial = np.array([coefBi[1, 1]*coefBi[3, 2] -
                                   coefBi[1, 2]*coefBi[3, 1],
                                   coefBi[0, 1]*coefBi[3, 2] +
                                   coefBi[1, 1]*coefBi[2, 2] -
                                   coefBi[0, 2]*coefBi[3, 1] -
                                   coefBi[2, 1]*coefBi[1, 2],
                                   coefBi[0, 1]*coefBi[2, 2] -
                                   coefBi[0, 2]*coefBi[2, 1]])
            roots_y = np.roots(polynomial)
            if len(roots_y) == 0:
                roots_y = -np.ones(2)
            if len(roots_y) == 1:
                roots_y = np.array([roots_y, roots_y])
            roots_z = -(coefBi[0, 1]+coefBi[1, 1]*roots_y)/ \
                       (coefBi[2, 1]+coefBi[3, 1]*roots_y)
            if np.real(roots_y[0]) >= 0 and np.real(roots_y[0]) <= 1 and\
            np.real(roots_z[0]) >= 0 and np.real(roots_z[0]) <= 1:
                intersection = True
                root_idx = 0
            if (np.real(roots_y[1]) >= 0 and np.real(roots_y[1]) <= 1) and \
            (np.real(roots_z[1]) >= 0 and np.real(roots_z[1]) <= 1):
                intersection = True
                root_idx = 1
            if intersection:
                xyz0 = [0, roots_y[root_idx], roots_z[root_idx]]
                xyz = np.real(__newton_raphson(xyz0, coefTri))
                # Check if the null point lies inside the cell.
                if np.all(xyz >= 0) and np.all(xyz <= 1):
                    null_cell.append([xyz[0]*var.dx + x[idx_x],
                                      xyz[1]*var.dy + y[idx_y],
                                      xyz[2]*var.dz + z[idx_z]])

            # face 6
            intersection = False
            coefBi = np.zeros((4, 3))
            coefBi[0] = coefTri[0] + coefTri[1]*1
            coefBi[1] = coefTri[2] + coefTri[3]*1
            coefBi[2] = coefTri[4] + coefTri[5]*1
            coefBi[3] = coefTri[6] + coefTri[7]*1
            # Find the roots for y0 and z0.
            polynomial = np.array([coefBi[1, 1]*coefBi[3, 2] -
                                   coefBi[1, 2]*coefBi[3, 1],
                                   coefBi[0, 1]*coefBi[3, 2] +
                                   coefBi[1, 1]*coefBi[2, 2] -
                                   coefBi[0, 2]*coefBi[3, 1] -
                                   coefBi[2, 1]*coefBi[1, 2],
                                   coefBi[0, 1]*coefBi[2, 2] -
                                   coefBi[0, 2]*coefBi[2, 1]])
            roots_y = np.roots(polynomial)
            if len(roots_y) == 0:
                roots_y = -np.ones(2)
            if len(roots_y) == 1:
                roots_y = np.array([roots_y, roots_y])
            roots_z = -(coefBi[0, 1]+coefBi[1, 1]*roots_y)/ \
                       (coefBi[2, 1]+coefBi[3, 1]*roots_y)
            if np.real(roots_y[0]) >= 0 and np.real(roots_y[0]) <= 1 and \
            np.real(roots_z[0]) >= 0 and np.real(roots_z[0]) <= 1:
                intersection = True
                root_idx = 0
            if np.real(roots_y[1]) >= 0 and np.real(roots_y[1]) <= 1 and \
            np.real(roots_z[1]) >= 0 and np.real(roots_z[1]) <= 1:
                intersection = True
                root_idx = 1
            if intersection:
                xyz0 = [1, roots_y[root_idx], roots_z[root_idx]]
                xyz = np.real(__newton_raphson(xyz0, coefTri))
                # Check if the null point lies inside the cell.
                if np.all(xyz >= 0) and np.all(xyz <= 1):
                    null_cell.append([xyz[0]*var.dx + x[idx_x],
                                      xyz[1]*var.dy + y[idx_y],
                                      xyz[2]*var.dz + z[idx_z]])

            # Compute the average of the null found from different faces.
            if null_cell:
                self.nulls.append(np.mean(null_cell, axis=0))

        # Discard null which are too close to each other.
        self.nulls = np.array(self.nulls)
        keep_null = np.ones(len(self.nulls), dtype=bool)
        for idx_null_1 in range(len(self.nulls)):
            for idx_null_2 in range(idx_null_1+1, len(self.nulls)):
                diff_nulls = abs(self.nulls[idx_null_1]-self.nulls[idx_null_2])
                if diff_nulls[0] < var.dx and diff_nulls[1] < var.dy and \
                diff_nulls[2] < var.dz:
                    keep_null[idx_null_2] = False
        self.nulls = self.nulls[keep_null == True]


    def write_vtk(self, data_dir='./data', file_name='nulls.vtk'):
        """
        Write the null point into a vtk file.

        call signature:

            write_vtk(data_dir='./data', file_name='nulls.vtk')

        Arguments:

        *data_dir*:
            Target data directory.

        *file_name*:
            Target file name.
        """

        writer = vtk.vtkPolyDataWriter()
        writer.SetFileName(os.path.join(data_dir, file_name))
        poly_data = vtk.vtkPolyData()
        points = vtk.vtkPoints()
        for null in self.nulls:
            points.InsertNextPoint(null)
        poly_data.SetPoints(points)
        writer.SetInputData(poly_data)
        writer.Write()

    def read_vtk(self, data_dir='./data', file_name='nulls.vtk'):
        """
        Read the null point from a vtk file.

        call signature:

            read_vtk(data_dir='./data', file_name='nulls.vtk')

        Arguments:

        *data_dir*:
            Origin data directory.

        *file_name*:
            Origin file name.
        """

        reader = vtk.vtkPolyDataReader()
        reader.SetFileName(os.path.join(data_dir, file_name))
        reader.Update()
        output = reader.GetOutput()
        points = output.GetPoints()
        self.nulls = []
        for null in range(points.GetNumberOfPoints()):
            self.nulls.append(points.GetPoint(null))
        self.nulls = np.array(self.nulls)


class Separatrix(object):
    """
    Contains the separatrix layers.
    """

    def __init__(self):
        """
        Fill members with default values.
        """

        self.lines = []
        self.eigen_values = []
        self.eigen_vectors = []
        self.sign_trace = []
        self.fan_vectors = []
        self.normals = []
        self.separatrices = []
        self.connectivity = []

    def find_separatrices(self, var, field, null_point, delta=0.1,
                          iter_max=100, ring_density=8):
        """
        Find the separatrices to the field 'field' with information from 'var'.

        call signature:

            find_separatrices(var, field, null_point, delta=0.1,
                              iter_max=100, density=8)

        Arguments:

        *var*:
            The var object from the read_var routine.

        *field*:
            The vector field.

        *null_point*:
            NullPoint object containing the magnetic null points.
            
        *delta*:
            Step length for the field line tracing.

        *iter_max*:
            Maximum iteration steps for the fiel line tracing.

        *ring_density*:
            Density of the tracer rings.
        """


        for null in null_point.nulls:
            # Find the Jacobian grad(field).
            grad_field = self.__grad_field(null, var, field,
                                           min((var.dx, var.dy, var.dz))/10)
            # Find the eigenvalues of the Jacobian.
            eigen_values = np.array(np.linalg.eig(grad_field)[0])
            # Find the eigenvectors of the Jacobian.
            eigen_vectors = np.array(np.linalg.eig(grad_field)[1].T)
            # Determine which way to trace the streamlines.
            if np.linalg.det(grad_field) < 0:
                sign_trace = 1
                fan_vectors = eigen_vectors[np.where(np.sign(eigen_values) > 0)]
            if np.linalg.det(grad_field) > 0:
                sign_trace = -1
                fan_vectors = eigen_vectors[np.where(np.sign(eigen_values) < 0)]
            if np.linalg.det(grad_field) == 0:
                print("error: Null point is not of x-type.")
                continue
            fan_vectors = np.array(fan_vectors)
            # Compute the normal to the fan-plane.
            normal = np.cross(fan_vectors[0], fan_vectors[1])
            normal = normal/np.sqrt(np.sum(normal**2))

            self.eigen_values.append(eigen_values)
            self.eigen_vectors.append(eigen_vectors)
            self.sign_trace.append(sign_trace)
            self.fan_vectors.append(fan_vectors)
            self.normals.append(normal)

            tracing = True
            separatrices = []
            connectivity = []
            separatrices.append(null)
            # Create the first ring of points.
            ring = []
            for theta in np.linspace(0, 2*np.pi*(1-1./ring_density), ring_density):
                ring.append(null + self.__rotate_vector(normal, fan_vectors[0],
                                                        theta) * delta)
                separatrices.append(ring[-1])
                # Set the connectivity with the null point.
                connectivity.append(np.array([0, len(ring)]))

            # Set the connectivity within the ring.
            for idx in range(ring_density-1):
                connectivity.append(np.array([idx+1, idx+2]))
            connectivity.append(np.array([1, ring_density]))
            
            # Trace the rings around the null.
            iteration = 0
            while tracing and iteration < iter_max:
                ring_old = ring
                
                # Trace field lines on ring.
                point_idx = 0
                for point in ring:
                    field_norm = vec_int(point, var, field)*sign_trace
                    field_norm = field_norm/np.sqrt(np.sum(field_norm**2))
                    point = point + field_norm*delta
                    ring[point_idx] = point
                    point_idx += 1

                # Add points if distance becomes too large.
                ring_new = []
                ring_new.append(ring[0])
                for point_idx in range(len(ring)-1):
                    if self.__distance(ring[point_idx], ring[point_idx+1]) > delta:
                        ring_new.append((ring[point_idx]+ring[point_idx+1])/2)
                    ring_new.append(ring[point_idx+1])
                if self.__distance(ring[0], ring[-1]) > delta:
                    ring_new.append((ring[0]+ring[-1])/2)
                ring = ring_new

                # Remove points which lie outside.
                ring_new = []
                for point_idx in range(len(ring)):
                    if self.__inside_domain(ring[point_idx], var):
                        ring_new.append(ring[point_idx])
                        separatrices.append(ring[point_idx])
                    
                # Set the connectivity within the ring.
                offset = len(separatrices)-len(ring_new)
                for point_idx in range(len(ring_new)-1):
                    connectivity.append(np.array([offset+point_idx,
                                                  offset+point_idx+1]))
                connectivity.append(np.array([offset, offset+len(ring_new)-1]))
                ring = ring_new
                
                offset = len(separatrices)-len(ring_old)-len(ring)
                # Compute connectivity arrays between the old and new ring.
                for point_old_idx in range(len(ring_old)):
                    point_old = ring_old[point_old_idx]
                    dist_min = np.inf
                    idx_min = -1
                    for point_idx in range(len(ring)):
                        point = ring[point_idx]
                        dist = self.__distance(point_old, point)
                        if dist < dist_min:
                            dist_min = dist
                            idx_min = point_idx
                    if idx_min > -1:
                        connectivity.append(np.array([offset+point_old_idx,
                                                      offset+idx_min+len(ring_old)]))
                
                iteration += 1
                # Stop the tracing routine if there are no points in the ring.
                if not ring:
                    tracing = False
            self.separatrices.append(np.array(separatrices))
            self.connectivity.append(np.array(connectivity))
        
        self.eigen_values = np.array(self.eigen_values)
        self.eigen_vectors = np.array(self.eigen_vectors)
        self.sign_trace = np.array(self.sign_trace)
        self.fan_vectors = np.array(self.fan_vectors)
        self.normals = np.array(self.normals)
        self.separatrices = np.array(self.separatrices)


    def write_vtk(self, data_dir='./data', file_name='separatrices.vtk'):
        """
        Write the separatrices into a vtk file.

        call signature:

            write_vtk(data_dir='./data', file_name='separatrices.vtk')

        Arguments:

        *data_dir*:
            Target data directory.

        *file_name*:
            Target file name.
        """

        writer = vtk.vtkUnstructuredGridWriter()
        writer.SetFileName(os.path.join(data_dir, file_name))
        grid_data = vtk.vtkUnstructuredGrid()
        points = vtk.vtkPoints()
        cell_array = vtk.vtkCellArray()
        offset = 0
        for idx in range(len(self.separatrices)):
            for point_idx in range(len(self.separatrices[idx])):
                points.InsertNextPoint(self.separatrices[idx][point_idx, :])
            for cell_idx in range(len(self.connectivity[idx])):
                cell_array.InsertNextCell(2)
                cell_array.InsertCellPoint(self.connectivity[idx][cell_idx, 0]
                                           +offset)
                cell_array.InsertCellPoint(self.connectivity[idx][cell_idx, 1]
                                           +offset)
            offset += point_idx+1
        grid_data.SetPoints(points)
        grid_data.SetCells(vtk.VTK_LINE, cell_array)
        writer.SetInput(grid_data)
        writer.Write()
        
        
    def __grad_field(self, xyz, var, field, dd):
        """ Compute the gradient if the field at xyz. """
        gf = np.zeros((3, 3))
        gf[0, :] = (vec_int(xyz+np.array([dd, 0, 0]), var, field) -
                    vec_int(xyz-np.array([dd, 0, 0]), var, field))/(2*dd)
        gf[1, :] = (vec_int(xyz+np.array([0, dd, 0]), var, field) -
                    vec_int(xyz-np.array([0, dd, 0]), var, field))/(2*dd)
        gf[2, :] = (vec_int(xyz+np.array([0, 0, dd]), var, field) -
                    vec_int(xyz-np.array([0, 0, dd]), var, field))/(2*dd)

        return np.matrix(gf)


    def __rotate_vector(self, rot_normal, vector, theta):
        """ Rotate vector around rot_normal by theta. """
        # Compute the rotation matrix.
        u = rot_normal[0]
        v = rot_normal[1]
        w = rot_normal[2]
        rot_matrix = np.matrix([[u**2+(1-u**2)*np.cos(theta),
                                 u*v*(1-np.cos(theta))-w*np.sin(theta),
                                 u*w*(1-np.cos(theta)+v*np.sin(theta))],
                                [u*v*(1-np.cos(theta)+w*np.sin(theta)),
                                 v**2+(1-v**2)*np.cos(theta),
                                 v*w*(1-np.cos(theta))-u*np.sin(theta)],
                                [u*w*(1-np.cos(theta))-v*np.sin(theta),
                                 v*w*(1-np.cos(theta))+u*np.sin(theta),
                                 w**2+(1-w**2)*np.cos(theta)]])
        return np.array(vector*rot_matrix)[0]
    
    
    def __distance(self, point_a, point_b):
        """ Compute the distance of two points (Euclidian geometry). """
        return np.sqrt(np.sum((point_a-point_b)**2))
    
    
    def __inside_domain(self, point, var):
        return (point[0] > var.x[0]) * (point[0] < var.x[-1]) * \
               (point[1] > var.y[0]) * (point[1] < var.y[-1]) * \
               (point[2] > var.z[0]) * (point[2] < var.z[-1])
        