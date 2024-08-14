# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause



folder_name = basename(@__FILE__)[1:end-3]
cd("fullscale_tests/" * folder_name) do
    run_perilab("correspondence_elastic_plastic", 1, true, folder_name)
    #    run_perilab("correspondence_strain_pstrain_x_yy", 1, true, folder_name)
end
